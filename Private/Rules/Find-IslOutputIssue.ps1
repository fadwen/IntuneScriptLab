function Find-IslOutputIssue {
    <#
    .SYNOPSIS
        Flags output that Intune will drop, truncate or misread.

    .DESCRIPTION
        Remediations report only the *last* line of the console output, capped at its last 2,048
        characters. That console output includes the host streams: a trailing Write-Host,
        Write-Warning ("WARNING: ...") or Write-Verbose -Verbose ("VERBOSE: ...") becomes the
        reported line and displaces the summary written before it. Win32 detection is stricter:
        the app counts as installed only when the script exits 0 *and* wrote something to
        stdout, and anything on stderr (Write-Error, a cmdlet's own error record, a throw) makes
        it "not detected" even then. Write-Host does count as stdout there; Write-Warning doesn't
        count as stderr. Platform scripts report everything, so no rule applies.

    .PARAMETER Context
        The IntuneScriptLab.ScriptContext from Get-IslScriptContext: AST, tokens, bytes and the
        effective ScriptType, Context and Architecture.

    .EXAMPLE
        Find-IslOutputIssue -Context (Get-IslScriptContext -Path .\Detect.ps1)

        The findings this rule produces for one script, as IntuneScriptLab.Finding objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $rule = 'IslOutputIssue'
    $type = $Context.ScriptType
    $ast = $Context.Ast
    $stdoutCommands = 'Write-Output', 'echo', 'write', 'Write-Host'
    $notCaptured = 'Write-Host', 'Write-Warning', 'Write-Verbose', 'Write-Information', 'Write-Debug'

    if ($type -in 'Detection', 'Remediation') {
        $hostEvidence = ('A trailing Write-Host, Write-Warning or Write-Verbose -Verbose was reported verbatim: ' +
            ('"host-last", "WARNING: warn-last", "VERBOSE: verbose-last" (REM-OUT-HOSTLAST/WARNLAST/VERBLAST); ' +
                'otherwise the last Write-Output line wins (REM-OUT-STREAMS)'))
        $hostCommands = @(Find-IslCommand -Ast $ast -Name $notCaptured)
        $outputs = @(Find-IslCommand -Ast $ast -Name 'Write-Output', 'echo', 'write')

        # Whatever writes last, in source order, is what Intune shows. Write-Verbose without
        # -Verbose prints nothing, so it can't displace anything.
        $writers = @($hostCommands | Where-Object {
                $_.GetCommandName() -ne 'Write-Verbose' -or
                (Test-IslCommandParameter -Command $_ -ParameterName 'Verbose')
            }) + $outputs
        $last = $writers | Sort-Object { $_.Extent.EndOffset } | Select-Object -Last 1
        if ($last -and $last.GetCommandName() -in $notCaptured) {
            $prefix = switch ($last.GetCommandName()) {
                'Write-Warning' { ' with a "WARNING: " prefix' }
                'Write-Verbose' { ' with a "VERBOSE: " prefix' }
                default { '' }
            }
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Warning'
                Context  = $Context
                Extent   = $last.Extent
                Message  = ("$($last.GetCommandName()) is the last thing written, so its text$prefix is what " +
                    'Intune reports instead of your summary. Write the summary line last, with Write-Output')
                Evidence = $hostEvidence
            }
            New-IslFinding @findingSplat
        }
        elseif ($hostCommands.Count -gt 0) {
            $names = ($hostCommands | ForEach-Object { $_.GetCommandName() } | Sort-Object -Unique) -join ', '
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Information'
                Context  = $Context
                Extent   = $hostCommands[0].Extent
                Message  = ("$names text lands in the same console output Intune reads; it is fine as logging " +
                    'as long as the summary Write-Output stays last')
                Evidence = $hostEvidence
            }
            New-IslFinding @findingSplat
        }
        if ($outputs.Count -gt 1) {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Information'
                Context  = $Context
                Extent   = $outputs[0].Extent
                Message  = ("$($outputs.Count) Write-Output calls: Intune reports only the last line " +
                    '(and only its last 2,048 characters). Put the summary last')
                Evidence = ('Last line only (REM-OUT-STREAMS); a 6,000-character line was reported as its ' +
                    'final 2,048 characters (REM-OUT-LONG)')
            }
            New-IslFinding @findingSplat
        }
    }

    if ($type -eq 'Remediation') {
        # The remediation script of a pair. Anything on its stderr makes the agent report a script
        # error and skip the post-detection, with exit 0 or not; the detection script's stderr
        # changes nothing (REM-DETECT-STDERR-EXIT0)
        $remediationEvidence = ('A remediation that wrote a cmdlet error to stderr and exited 0 was reported ' +
            'as RemediationStatus 3, Graph remediationState scriptError, no post-detection run; the same ' +
            'script with the error silenced ran the post-detection and was reported Recurred ' +
            '(REM-STDERR-EXIT0, REM-STDERR-SILENT)')
        foreach ($command in (Find-IslCommand -Ast $ast -Name 'Write-Error')) {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Warning'
                Context  = $Context
                Extent   = $command.Extent
                Message  = ('Write-Error puts text on stderr: Intune reports the remediation as a script error ' +
                    'and skips the post-detection even when the script exits 0. Exit non-zero to fail on ' +
                    'purpose, or report the problem with Write-Output')
                Evidence = $remediationEvidence
            }
            New-IslFinding @findingSplat
        }
        $probing = 'Get-Item', 'Get-ItemProperty', 'Get-ItemPropertyValue', 'Get-ChildItem', 'Get-Package',
            'Get-Service', 'Get-Process', 'Get-WmiObject', 'Get-CimInstance', 'Get-AppxPackage',
            'Set-ItemProperty', 'New-ItemProperty', 'Remove-Item', 'Remove-ItemProperty', 'Copy-Item', 'Move-Item'
        $unguarded = @(Find-IslCommand -Ast $ast -Name $probing |
            Where-Object { -not (Test-IslCommandParameter -Command $_ -ParameterName 'ErrorAction') })
        $preferenceSet = Find-IslAstNode -Ast $ast -TypeName AssignmentStatementAst -Where {
            param($node) $node.Left.Extent.Text -match '(?i)^\$ErrorActionPreference$' -and
                $node.Right.Extent.Text -match '(?i)SilentlyContinue|Ignore|Stop'
        }
        if ($unguarded.Count -gt 0 -and -not $preferenceSet) {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Warning'
                Context  = $Context
                Extent   = $unguarded[0].Extent
                Message  = ("$($unguarded[0].GetCommandName()) writes an error record to stderr when its target " +
                    'is missing, and the script carries on to exit 0: Intune then reports a script error, not ' +
                    'the Recurred the post-detection would have given. Use -ErrorAction Stop and let the ' +
                    'failure be one, or check the target first')
                Evidence = $remediationEvidence
                Fix      = @{ Replacement = $unguarded[0].Extent.Text + ' -ErrorAction Stop' }
            }
            New-IslFinding @findingSplat
        }
    }

    if ($type -eq 'Win32Detection') {
        $stderrCommands = @(Find-IslCommand -Ast $ast -Name 'Write-Error')
        foreach ($command in $stderrCommands) {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Error'
                Context  = $Context
                Extent   = $command.Extent
                Message  = ('Write-Error puts text on stderr: the app is reported as not detected even with ' +
                    'exit 0 and stdout')
                Evidence = ('exit 0 + "installed" + Write-Error: AgentExecutor reported exitCode -1, ' +
                    'applicationDetected False (W32-DET-STDERR)')
            }
            New-IslFinding @findingSplat
        }
        $stderrMembers = Find-IslAstNode -Ast $ast -TypeName InvokeMemberExpressionAst -Where {
            param($node) $node.Extent.Text -match '(?i)\[Console\]::Error\.|\.UI\.WriteErrorLine'
        }
        foreach ($node in $stderrMembers) {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Error'
                Context  = $Context
                Extent   = $node.Extent
                Message  = ('Writing to the error stream makes the app "not detected" regardless of exit code ' +
                    'and stdout')
                Evidence = 'Any stderr output → not detected (W32-DET-STDERR)'
            }
            New-IslFinding @findingSplat
        }

        $stdout = @(Find-IslCommand -Ast $ast -Name $stdoutCommands)
        # A bare expression statement at script scope also writes to stdout
        $bareOutput = @(Find-IslAstNode -Ast $ast -TypeName PipelineAst -Where {
                param($node)
                $node.Parent.GetType().Name -in 'NamedBlockAst', 'StatementBlockAst' -and
                $node.PipelineElements.Count -eq 1 -and
                $node.PipelineElements[0].GetType().Name -ne 'CommandAst' -and
                -not (Test-IslInsideFunction -Node $node)
            })
        $exitZero = @(Find-IslAstNode -Ast $ast -TypeName ExitStatementAst -Where {
                param($node) -not $node.Pipeline -or $node.Pipeline.Extent.Text.Trim() -eq '0'
            })
        if ($stdout.Count -eq 0 -and $bareOutput.Count -eq 0) {
            $extent = if ($exitZero) { $exitZero[0].Extent } else { $ast.Extent }
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Error'
                Context  = $Context
                Extent   = $extent
                Message  = ('Nothing is ever written to stdout: exit 0 alone means "not detected". ' +
                    'Write-Output a line before exit 0 on the installed path')
                Evidence = 'exit 0 with no stdout → NotDetected → install ran → 0x87D1041C (W32-DET-NOOUT)'
            }
            New-IslFinding @findingSplat
        }

        # Cmdlet error records also go to stderr
        $probing = 'Get-Item', 'Get-ItemProperty', 'Get-ItemPropertyValue', 'Get-ChildItem', 'Get-Package',
            'Get-Service', 'Get-Process', 'Get-WmiObject', 'Get-CimInstance', 'Get-AppxPackage'
        $unguarded = @(Find-IslCommand -Ast $ast -Name $probing |
            Where-Object { -not (Test-IslCommandParameter -Command $_ -ParameterName 'ErrorAction') })
        $preferenceSet = Find-IslAstNode -Ast $ast -TypeName AssignmentStatementAst -Where {
            param($node) $node.Left.Extent.Text -match '(?i)^\$ErrorActionPreference$' -and
                $node.Right.Extent.Text -match '(?i)SilentlyContinue|Ignore'
        }
        if ($unguarded.Count -gt 0 -and -not $preferenceSet) {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Warning'
                Context  = $Context
                Extent   = $unguarded[0].Extent
                Message  = ("$($unguarded[0].GetCommandName()) writes an error record to stderr when its " +
                    "target is missing, which makes the app 'not detected'. Use -ErrorAction " +
                    'SilentlyContinue (or Test-Path first) on the not-installed path')
                Evidence = ('A non-terminating cmdlet error appeared in the captured error output ' +
                    '(REM-EXIT-ERRNOEXIT); any stderr fails Win32 detection (W32-DET-STDERR)')
                Fix      = @{ Replacement = $unguarded[0].Extent.Text + ' -ErrorAction SilentlyContinue' }
            }
            New-IslFinding @findingSplat
        }
    }

    if ($type -eq 'Win32Requirement') {
        # The rule compares the whole stdout, minus its final line break, with the portal value:
        # one Write-Output of exactly that value, exit 0, nothing on stderr
        $wholeEvidence = ('"first" then "ok" and "ok" then "second" both failed string equal ok; "ok   " ' +
            'failed too (W32-REQ-LASTLINE, W32-REQ-FIRSTLINE, W32-REQ-TRAIL)')
        foreach ($command in (Find-IslCommand -Ast $ast -Name 'Write-Error')) {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Error'
                Context  = $Context
                Extent   = $command.Extent
                Message  = ('Write-Error puts text on stderr: the rule fails even with exit 0 and the right ' +
                    'output')
                Evidence = '"ok" plus Write-Error with exit 0: not applicable (W32-REQ-STDERR)'
            }
            New-IslFinding @findingSplat
        }
        # Write-Host text is part of the compared output (Write-Host "ok" met the rule on the device),
        # so a logging Write-Host next to the value is a second line, and a second line never matches
        $outputs = @(Find-IslCommand -Ast $ast -Name $stdoutCommands)
        $bareOutput = @(Find-IslAstNode -Ast $ast -TypeName PipelineAst -Where {
                param($node)
                $node.Parent.GetType().Name -in 'NamedBlockAst', 'StatementBlockAst' -and
                $node.PipelineElements.Count -eq 1 -and
                $node.PipelineElements[0].GetType().Name -ne 'CommandAst' -and
                -not (Test-IslInsideFunction -Node $node)
            })
        $writers = @($outputs) + @($bareOutput)
        if ($writers.Count -eq 0) {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Error'
                Context  = $Context
                Extent   = $ast.Extent
                Message  = ('Nothing is written to stdout, so the rule has nothing to compare and fails. ' +
                    'Write-Output the value the rule expects')
                Evidence = 'No output against string equal ok: not applicable (W32-REQ-NOOUT)'
            }
            New-IslFinding @findingSplat
        }
        elseif ($writers.Count -gt 1) {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Warning'
                Context  = $Context
                Extent   = $writers[1].Extent
                Message  = ("$($writers.Count) statements write to the console (Write-Host included): the " +
                    'rule compares the whole output, so a second line means no match. Write exactly one value')
                Evidence = ($wholeEvidence + '; Write-Host "ok" alone met the rule (W32-REQ-HOST)')
            }
            New-IslFinding @findingSplat
        }
        foreach ($command in $outputs) {
            $literal = $command.CommandElements | Select-Object -Skip 1 | Where-Object {
                $_.GetType().Name -eq 'StringConstantExpressionAst' -and $_.Value -ne $_.Value.Trim()
            } | Select-Object -First 1
            if ($literal) {
                $findingSplat = @{
                    RuleName = $rule
                    Severity = 'Warning'
                    Context  = $Context
                    Extent   = $literal.Extent
                    Message  = ('The output has leading or trailing whitespace, which the rule does not trim, ' +
                        'so it will not match the portal value')
                    Evidence = $wholeEvidence
                    # The literal's own quotes around its trimmed source text, escapes untouched
                    Fix      = @{
                        Replacement = $literal.Extent.Text.Substring(0, 1) +
                            $literal.Extent.Text.Substring(1, $literal.Extent.Text.Length - 2).Trim() +
                            $literal.Extent.Text.Substring($literal.Extent.Text.Length - 1)
                    }
                }
                New-IslFinding @findingSplat
            }
        }
        $exits = @(Find-IslAstNode -Ast $ast -TypeName ExitStatementAst -Where {
                param($node) $node.Pipeline -and $node.Pipeline.Extent.Text.Trim() -ne '0'
            })
        foreach ($exit in $exits) {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Information'
                Context  = $Context
                Extent   = $exit.Extent
                Message  = ('A non-zero exit fails the rule without looking at the output; fine as a ' +
                    'deliberate "not applicable", surprising if the output was meant to decide')
                Evidence = '"ok" with exit 1 against string equal ok: not applicable (W32-REQ-EXIT1)'
            }
            New-IslFinding @findingSplat
        }
        $probing = 'Get-Item', 'Get-ItemProperty', 'Get-ItemPropertyValue', 'Get-ChildItem', 'Get-Package',
            'Get-Service', 'Get-Process', 'Get-WmiObject', 'Get-CimInstance', 'Get-AppxPackage'
        $unguarded = @(Find-IslCommand -Ast $ast -Name $probing |
            Where-Object { -not (Test-IslCommandParameter -Command $_ -ParameterName 'ErrorAction') })
        $preferenceSet = Find-IslAstNode -Ast $ast -TypeName AssignmentStatementAst -Where {
            param($node) $node.Left.Extent.Text -match '(?i)^\$ErrorActionPreference$' -and
                $node.Right.Extent.Text -match '(?i)SilentlyContinue|Ignore'
        }
        if ($unguarded.Count -gt 0 -and -not $preferenceSet) {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Warning'
                Context  = $Context
                Extent   = $unguarded[0].Extent
                Message  = ("$($unguarded[0].GetCommandName()) writes an error record to stderr when its " +
                    'target is missing, which fails the rule. Use -ErrorAction SilentlyContinue or ' +
                    'Test-Path first')
                Evidence = 'Any stderr fails the rule (W32-REQ-STDERR)'
                Fix      = @{ Replacement = $unguarded[0].Extent.Text + ' -ErrorAction SilentlyContinue' }
            }
            New-IslFinding @findingSplat
        }
    }
}
