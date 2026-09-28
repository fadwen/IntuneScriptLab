function Find-IslInteractiveCall {
    <#
    .SYNOPSIS
        Flags anything that waits for a person.

    .DESCRIPTION
        The agent launches powershell.exe with -NoProfile -ExecutionPolicy Bypass -File and
        nothing else: no -NonInteractive. A prompt therefore doesn't fail, it waits, until the
        agent kills the script at its timeout (30 minutes for platform scripts, 60 for
        remediations and Win32 detection). Remediations run one at a time, so one hung script
        also delays every other remediation on the device.

    .PARAMETER Context
        The IntuneScriptLab.ScriptContext from Get-IslScriptContext: AST, tokens, bytes and the
        effective ScriptType, Context and Architecture.

    .EXAMPLE
        Find-IslInteractiveCall -Context (Get-IslScriptContext -Path .\Detect.ps1)

        The findings this rule produces for one script, as IntuneScriptLab.Finding objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $rule = 'IslInteractiveCall'
    $timeout = if ($Context.ScriptType -eq 'PlatformScript') { '30 minutes' } else { '60 minutes' }
    $evidence = ("Launched as powershell.exe -NoProfile -executionPolicy bypass -file, without -NonInteractive; " +
        "AgentExecutor timeout $timeout (PS-PROBE-SYS64, REM-PROBE-SYS64, Win32 log)")
    $ast = $Context.Ast

    $alwaysPrompt = 'Read-Host', 'Pause', 'Out-GridView', 'Show-Command', 'Get-Credential'
    foreach ($command in (Find-IslCommand -Ast $ast -Name $alwaysPrompt)) {
        $name = $command.GetCommandName()
        if ($name -eq 'Get-Credential' -and $command.CommandElements.Count -gt 1) {
            # Get-Credential with a name/message still prompts; only a fully built credential doesn't
        }
        $findingSplat = @{
            RuleName = $rule
            Severity = 'Error'
            Context  = $Context
            Extent   = $command.Extent
            Message  = "$name waits for input that never comes; the script hangs until the $timeout timeout"
            Evidence = $evidence
        }
        New-IslFinding @findingSplat
    }

    $hostPrompts = Find-IslAstNode -Ast $ast -TypeName InvokeMemberExpressionAst -Where {
        param($node)
        $member = "$($node.Member.Value)"
        ($member -in 'ReadLine', 'ReadKey', 'Prompt', 'PromptForChoice', 'PromptForCredential') -and
        ($node.Expression.Extent.Text -match '(?i)console|host|RawUI|\bUI\b')
    }
    foreach ($node in $hostPrompts) {
        $findingSplat = @{
            RuleName = $rule
            Severity = 'Error'
            Context  = $Context
            Extent   = $node.Extent
            Message  = ("$($node.Expression.Extent.Text).$($node.Member.Value)() waits for input; the script " +
                "hangs until the $timeout timeout")
            Evidence = $evidence
        }
        New-IslFinding @findingSplat
    }

    # Cmdlets that confirm unless told not to
    $confirming = @{
        'Set-ExecutionPolicy'     = 'Force'
        'Install-Module'          = 'Force'
        'Install-PackageProvider' = 'Force'
        'Install-Package'         = 'Force'
        'Update-Module'           = 'Force'
        'Uninstall-Module'        = 'Force'
        'Register-PSRepository'   = ''
    }
    foreach ($commandName in $confirming.Keys) {
        foreach ($command in (Find-IslCommand -Ast $ast -Name $commandName)) {
            $forced = $confirming[$commandName] -and
                (Test-IslCommandParameter -Command $command -ParameterName $confirming[$commandName])
            $silenced = $forced -or (Test-IslCommandParameter -Command $command -ParameterName 'Confirm')
            if (-not $silenced) {
                $findingSplat = @{
                    RuleName = $rule
                    Severity = 'Warning'
                    Context  = $Context
                    Extent   = $command.Extent
                    Message  = ("$commandName can prompt for confirmation (or to trust a repository); add " +
                        "-Force / -Confirm:`$false or it hangs until the $timeout timeout")
                    Evidence = $evidence
                }
                New-IslFinding @findingSplat
            }
        }
    }
}
