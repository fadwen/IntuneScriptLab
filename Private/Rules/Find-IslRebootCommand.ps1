function Find-IslRebootCommand {
    <#
    .SYNOPSIS
        Flags restarts and shutdowns issued from inside a script.

    .DESCRIPTION
        Microsoft says not to put reboot commands in detection or remediation scripts. A reboot
        from a script kills the agent's run mid-flight: the result is never reported and the
        remediation queue is thrown away. Win32 apps have a supported channel for this, return
        code 3010 (soft reboot).

    .PARAMETER Context
        The IntuneScriptLab.ScriptContext from Get-IslScriptContext: AST, tokens, bytes and the
        effective ScriptType, Context and Architecture.

    .EXAMPLE
        Find-IslRebootCommand -Context (Get-IslScriptContext -Path .\Detect.ps1)

        The findings this rule produces for one script, as IntuneScriptLab.Finding objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $rule = 'IslRebootCommand'
    $ast = $Context.Ast
    $evidence = ('Microsoft Learn (Remediations): "Don''t put reboot commands in detection or remediations ' +
        'scripts"; an IME restart discards the queued remediation run (observed)')

    $found = @(Find-IslCommand -Ast $ast -Name 'Restart-Computer', 'Stop-Computer')
    $found += @(Find-IslCommand -Ast $ast -Name 'shutdown', 'shutdown.exe' |
        Where-Object { $_.Extent.Text -match '(?i)\s[/-][rsg]\b' })

    foreach ($command in $found) {
        $message = switch ($Context.ScriptType) {
            'Win32Detection' { ('A detection script must not restart the device; signal a pending reboot from ' +
                'the ' +
                'install command with return code 3010 instead') }
            'Win32Requirement' { 'A requirement script must not restart the device' }
            'PlatformScript' { ('Restarting from a platform script ends the run before the result is reported; ' +
                'prefer a scheduled restart or a separate policy') }
            default { 'Restarting from a detection or remediation script is unsupported and loses the run result' }
        }
        $severity = if ($Context.ScriptType -in 'Detection', 'Remediation', 'Win32Detection',
            'Win32Requirement') { 'Warning' } else { 'Information' }
        $findingSplat = @{
            RuleName = $rule
            Severity = $severity
            Context  = $Context
            Extent   = $command.Extent
            Message  = $message
            Evidence = $evidence
        }
        New-IslFinding @findingSplat
    }
}
