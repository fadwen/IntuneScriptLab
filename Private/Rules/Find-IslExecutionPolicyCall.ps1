function Find-IslExecutionPolicyCall {
    <#
    .SYNOPSIS
        Flags Set-ExecutionPolicy calls, which the agent's own launch makes redundant or harmful.

    .DESCRIPTION
        Every script the agent runs is launched as
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File <script> (AgentExecutor.log, all
        rounds), so the process already runs with Bypass and a Set-ExecutionPolicy -Scope Process
        changes nothing. Any other scope is a change to the machine or the user policy made as
        SYSTEM on every run: a side effect that outlives the script and does nothing for it.

    .PARAMETER Context
        The IntuneScriptLab.ScriptContext from Get-IslScriptContext: AST, tokens, bytes and the
        effective ScriptType, Context and Architecture.

    .EXAMPLE
        Find-IslExecutionPolicyCall -Context (Get-IslScriptContext -Path .\Detect.ps1)

        The findings this rule produces for one script, as IntuneScriptLab.Finding objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $rule = 'IslExecutionPolicyCall'
    $evidence = ('AgentExecutor launches every script with -NoProfile -ExecutionPolicy Bypass -File ' +
        '(AgentExecutor.log); Get-ExecutionPolicy -List inside a remediation reported the process scope as ' +
        'Bypass with the machine scopes untouched (REM-EXECPOLICY)')

    foreach ($command in (Find-IslCommand -Ast $Context.Ast -Name 'Set-ExecutionPolicy')) {
        $elements = $command.CommandElements
        $scope = 'LocalMachine'
        for ($i = 1; $i -lt $elements.Count; $i++) {
            $element = $elements[$i]
            $next = if ($i + 1 -lt $elements.Count) { $elements[$i + 1] } else { $null }
            if ($element.GetType().Name -eq 'CommandParameterAst' -and
                'Scope'.StartsWith($element.ParameterName, 'OrdinalIgnoreCase') -and $next) {
                $scope = $next.Extent.Text.Trim("'", '"')
            }
        }
        if ($scope -eq 'Process') {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Information'
                Context  = $Context
                Extent   = $command.Extent
                Message  = ('Set-ExecutionPolicy -Scope Process does nothing here: the agent already launches ' +
                    'the script with -ExecutionPolicy Bypass')
                Evidence = $evidence
            }
        }
        else {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Warning'
                Context  = $Context
                Extent   = $command.Extent
                Message  = ("Set-ExecutionPolicy with scope $scope changes the device's policy on every run and " +
                    'does nothing for this script, which the agent launches with -ExecutionPolicy Bypass. ' +
                    'Remove it')
                Evidence = $evidence
            }
        }
        New-IslFinding @findingSplat
    }
}
