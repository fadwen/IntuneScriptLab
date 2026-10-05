function Find-IslExitCodeIssue {
    <#
    .SYNOPSIS
        Flags exit-code mistakes in detection and remediation scripts.

    .DESCRIPTION
        Observed rules for remediations: the remediation script runs on *any* non-zero detection
        exit code (2 and -1 both triggered it), not only on 1 as documented. A `return` at script
        scope ends the script with exit 0, so `return $x; exit 1`, the pattern in Microsoft's own
        sample scripts, never triggers a remediation. An unhandled `throw` exits 1, which does
        trigger it, and then the post-detection throws again and the status becomes Recurred.
        Falling off the end without `exit` is exit 0: "without issues".

    .PARAMETER Context
        The IntuneScriptLab.ScriptContext from Get-IslScriptContext: AST, tokens, bytes and the
        effective ScriptType, Context and Architecture.

    .EXAMPLE
        Find-IslExitCodeIssue -Context (Get-IslScriptContext -Path .\Detect.ps1)

        The findings this rule produces for one script, as IntuneScriptLab.Finding objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $rule = 'IslExitCodeIssue'
    $type = $Context.ScriptType

    # The edit that says what a script-scope return already does: exit 0, after any value it returned
    function Get-ReturnReplacement {
        param($Return)
        if ($Return.Pipeline) { "$($Return.Pipeline.Extent.Text); exit 0" } else { 'exit 0' }
    }

    # An exit other than 0 after the return in the same block is the exit the author meant. Writing
    # 'exit 0' in front of it would leave it unreachable with no finding left to say so, so that
    # return gets no edit and stays reported
    function Test-ExitFollowsReturn {
        param($Return)
        $passed = $false
        foreach ($statement in @($Return.Parent.Statements)) {
            if ($statement -eq $Return) { $passed = $true; continue }
            if (-not $passed -or $statement.GetType().Name -ne 'ExitStatementAst') { continue }
            if ($statement.Pipeline -and $statement.Pipeline.Extent.Text.Trim() -ne '0') { return $true }
        }
        $false
    }
    if ($type -notin 'Detection', 'Remediation', 'Win32Detection') { return }
    $ast = $Context.Ast

    $exits = @(Find-IslAstNode -Ast $ast -TypeName ExitStatementAst)
    $topLevelReturns = @(Find-IslAstNode -Ast $ast -TypeName ReturnStatementAst -Where {
            param($node) -not (Test-IslInsideFunction -Node $node)
        })
    $unhandledThrows = @(Find-IslAstNode -Ast $ast -TypeName ThrowStatementAst -Where {
            param($node)
            -not (Test-IslInsideFunction -Node $node) -and -not (Test-IslInsideTryWithCatch -Node $node)
        })

    if ($type -eq 'Detection') {
        if ($exits.Count -eq 0) {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Warning'
                Context  = $Context
                Extent   = $ast.Extent
                Message  = ('No exit statement: the script always ends with exit 0 ("without issues") and the ' +
                    'remediation never runs')
                Evidence = ('A detection with no exit reported FirstDetectExitCode=0, status "without issues" ' +
                    '(REM-EXIT-NONE)')
            }
            New-IslFinding @findingSplat
        }
        foreach ($return in $topLevelReturns) {
            $severity = if ($exits.Count -gt 0) { 'Error' } else { 'Warning' }
            $findingSplat = @{
                RuleName = $rule
                Severity = $severity
                Context  = $Context
                Extent   = $return.Extent
                Message  = ('return at script scope ends the script with exit 0; any exit 1 after it never ' +
                    'runs, so the remediation never triggers. Use exit 1 directly')
                Evidence = ('"return 1; exit 1" ran with exit code 0 and the remediation was skipped; ' +
                    'Microsoft''s sample detection scripts use this pattern (REM-RETURN-EXIT)')
            }
            if (-not (Test-ExitFollowsReturn -Return $return)) {
                $findingSplat.Fix = @{ Replacement = Get-ReturnReplacement -Return $return }
            }
            New-IslFinding @findingSplat
        }
        foreach ($exit in $exits) {
            $value = $exit.Pipeline
            if (-not $value) { continue }
            $constant = $value.Extent.Text.Trim()
            if ($constant -match '^-?\d+$') {
                if ([int]$constant -notin 0, 1) {
                    $findingSplat = @{
                        RuleName = $rule
                        Severity = 'Warning'
                        Context  = $Context
                        Extent   = $exit.Extent
                        Message  = ("exit ${constant}: Intune treats every non-zero exit as 'issue found' and " +
                            'runs the remediation, then reports Recurred when the post-detection returns it ' +
                            "again. Use exit 1 for 'issue found'")
                        Evidence = ('exit 2 and exit -1 both triggered the remediation and ended as Recurred ' +
                            '(REM-EXIT-2, REM-EXIT-NEG1); docs say only exit 1 does')
                    }
                    New-IslFinding @findingSplat
                }
            }
            else {
                $findingSplat = @{
                    RuleName = $rule
                    Severity = 'Information'
                    Context  = $Context
                    Extent   = $exit.Extent
                    Message  = "exit with a computed value ($constant): make sure it is only ever 0 or 1"
                    Evidence = 'Any non-zero exit runs the remediation (REM-EXIT-2, REM-EXIT-NEG1)'
                }
                New-IslFinding @findingSplat
            }
        }
        foreach ($throw in $unhandledThrows) {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Warning'
                Context  = $Context
                Extent   = $throw.Extent
                Message  = ('Unhandled throw exits 1, so the remediation runs; the post-detection then throws ' +
                    'again and the status becomes Recurred. Catch it and decide on exit 0 or 1 explicitly')
                Evidence = ('A detection that threw exited 1, ran the remediation and reported Recurred ' +
                    '(REM-EXIT-THROW)')
            }
            New-IslFinding @findingSplat
        }
    }

    if ($type -eq 'Remediation') {
        foreach ($throw in $unhandledThrows) {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Warning'
                Context  = $Context
                Extent   = $throw.Extent
                Message  = ('Unhandled throw makes the remediation exit 1: Intune reports it as failed and ' +
                    'skips the post-detection')
                Evidence = ('A remediation exiting non-zero reported RemediationStatus=3 (failed) with no ' +
                    'post-detection run (REM-REMFAIL)')
            }
            New-IslFinding @findingSplat
        }
        foreach ($return in $topLevelReturns) {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Information'
                Context  = $Context
                Extent   = $return.Extent
                Message  = ('return at script scope ends the remediation with exit 0 (success) regardless of ' +
                    'what was actually done')
                Evidence = 'Script-scope return produced exit code 0 (REM-RETURN-EXIT)'
            }
            if (-not (Test-ExitFollowsReturn -Return $return)) {
                $findingSplat.Fix = @{ Replacement = Get-ReturnReplacement -Return $return }
            }
            New-IslFinding @findingSplat
        }
    }

    if ($type -eq 'Win32Detection') {
        foreach ($throw in $unhandledThrows) {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Warning'
                Context  = $Context
                Extent   = $throw.Extent
                Message  = 'Unhandled throw exits 1 and writes to stderr: the app is reported as not detected'
                Evidence = 'Detection script that threw: exit 1, applicationDetected: False (W32-DET-THROW)'
            }
            New-IslFinding @findingSplat
        }
        if ($exits.Count -eq 0) {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Information'
                Context  = $Context
                Extent   = $ast.Extent
                Message  = ('No exit statement: the script ends with exit 0, so detection depends entirely on ' +
                    'whether anything was written to stdout')
                Evidence = 'Exit 0 without stdout is "not detected" (W32-DET-NOOUT)'
            }
            New-IslFinding @findingSplat
        }
    }
}
