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
    $builtEvidence = ($evidence + '; handed a PSCredential object, Get-Credential -Credential returned it ' +
        'in 12 ms under the agent, without a prompt (REM-CRED-BUILT)')
    $ast = $Context.Ast


    $alwaysPrompt = 'Read-Host', 'Pause', 'Out-GridView', 'Show-Command', 'Get-Credential'
    foreach ($command in (Find-IslCommand -Ast $ast -Name $alwaysPrompt)) {
        $name = $command.GetCommandName()
        # Get-Credential -Credential returns a credential that is already built and prompts for the
        # password of a user name. A literal is a name; an expression or variable that can only
        # hold a credential never prompts; anything else cannot be told apart here
        $handed = if ($name -eq 'Get-Credential') { Get-IslCredentialArgument -Command $command }
        $literalTypes = 'StringConstantExpressionAst', 'ExpandableStringExpressionAst'
        $source = if ($handed -and $handed.GetType().Name -eq 'VariableExpressionAst') {
            Get-IslVariableCredentialSource -Variable $handed -Ast $ast
        }
        elseif ($handed) { Get-IslCredentialSource -Expression $handed }
        if ($source) {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Information'
                Context  = $Context
                Extent   = $command.Extent
                Message  = ("Get-Credential -Credential returns $($handed.Extent.Text) as it is: it comes from " +
                    "$source, so it is a credential that is already built and nothing prompts; the call " +
                    'can go')
                Evidence = $builtEvidence
                # The call returns what it was handed, so the argument stands in for it
                Fix      = @{ Replacement = $handed.Extent.Text }
            }
            New-IslFinding @findingSplat
            continue
        }
        if ($handed -and $handed.GetType().Name -notin $literalTypes) {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Warning'
                Context  = $Context
                Extent   = $command.Extent
                Message  = ('Get-Credential -Credential returns a credential that is already built and ' +
                    "prompts for the password of a user name: if $($handed.Extent.Text) can ever be a " +
                    "name, the script hangs until the $timeout timeout")
                Evidence = $builtEvidence
            }
            New-IslFinding @findingSplat
            continue
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
            $silenced = $forced -or ($command.Extent.Text -match '(?i)-Confirm:\s*\$false')
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
                # The switch the message asks for, added to the call. Set-ExecutionPolicy gets none: the
                # agent launches with -ExecutionPolicy Bypass, and IslExecutionPolicyCall removes the call
                if ($commandName -ne 'Set-ExecutionPolicy') {
                    $switch = if ($confirming[$commandName]) { " -$($confirming[$commandName])" }
                    else { ' -Confirm:$false' }
                    $findingSplat.Fix = @{ Replacement = $command.Extent.Text + $switch }
                }
                New-IslFinding @findingSplat
            }
        }
    }
}
