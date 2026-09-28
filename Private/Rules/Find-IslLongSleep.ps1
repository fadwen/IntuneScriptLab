function Find-IslLongSleep {
    <#
    .SYNOPSIS
        Flags waits long enough to hit the agent's timeout or hold up other remediations.

    .DESCRIPTION
        Platform scripts are killed after 30 minutes, remediations and Win32 detection after
        60. Remediations also run strictly one after another, so a long wait in one delays
        every other remediation assigned to the device.

    .PARAMETER Context
        The IntuneScriptLab.ScriptContext from Get-IslScriptContext: AST, tokens, bytes and the
        effective ScriptType, Context and Architecture.

    .EXAMPLE
        Find-IslLongSleep -Context (Get-IslScriptContext -Path .\Detect.ps1)

        The findings this rule produces for one script, as IntuneScriptLab.Finding objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $rule = 'IslLongSleep'
    $limitSeconds = if ($Context.ScriptType -eq 'PlatformScript') { 1800 } else { 3600 }
    $evidence = ("AgentExecutor.log: process timeout $limitSeconds s (W32-DET-PROBE); the 17 remediations of " +
        'round 1 ran one after another at ~15 s each, ~6 minutes for the batch (REM-PROBE-SYS64 and the ' +
        'other REM-* of round 1)')

    foreach ($command in (Find-IslCommand -Ast $Context.Ast -Name 'Start-Sleep', 'sleep')) {
        $seconds = $null
        $elements = $command.CommandElements
        for ($i = 1; $i -lt $elements.Count; $i++) {
            $element = $elements[$i]
            $next = if ($i + 1 -lt $elements.Count) { $elements[$i + 1] } else { $null }
            $isParameter = $element.GetType().Name -eq 'CommandParameterAst'
            if ($isParameter -and $next -and $next.Extent.Text -match '^\d+$') {
                if ('Seconds'.StartsWith($element.ParameterName,
                    'OrdinalIgnoreCase')) { $seconds = [int]$next.Extent.Text }
                elseif ('Milliseconds'.StartsWith($element.ParameterName,
                    'OrdinalIgnoreCase')) { $seconds = [int]$next.Extent.Text / 1000 }
            }
            elseif ($i -eq 1 -and $element.Extent.Text -match '^\d+$') { $seconds = [int]$element.Extent.Text }
        }
        if ($null -eq $seconds) { continue }
        if ($seconds -ge $limitSeconds) {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Error'
                Context  = $Context
                Extent   = $command.Extent
                Message  = ("Sleeping $seconds s exceeds the $limitSeconds s timeout; the script is killed " +
                    'before it finishes')
                Evidence = $evidence
            }
            New-IslFinding @findingSplat
        }
        elseif ($seconds -ge 300) {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Warning'
                Context  = $Context
                Extent   = $command.Extent
                Message  = ("Sleeping $seconds s holds the agent: remediations run one at a time and the " +
                    "whole script must finish within $limitSeconds s")
                Evidence = $evidence
            }
            New-IslFinding @findingSplat
        }
    }
}
