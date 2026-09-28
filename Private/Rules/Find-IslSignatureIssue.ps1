function Find-IslSignatureIssue {
    <#
    .SYNOPSIS
        Flags a Win32 detection script that the agent will refuse to run under a signature check.

    .DESCRIPTION
        With "Enforce script signature check" on a Win32 PowerShell detection rule, the agent hands the
        script to AgentExecutor, which returns exit 1 without running it when the script is not
        signed (no probe record, log "EnforceSignatureCheck: 1 ... applicationDetected: False",
        W32-DET-SIGCHECK). The app is then "not detected", the install runs, and the app ends in
        0x87D1041C, not detected after installation. The rule applies when the context says the check
        is on: -EnforceSignatureCheck on Test-IntuneScript, or the directive
        # IntuneScriptLab: EnforceSignatureCheck=true in the script.

    .PARAMETER Context
        The IntuneScriptLab.ScriptContext from Get-IslScriptContext: AST, tokens, bytes and the
        effective ScriptType, Context, Architecture and EnforceSignatureCheck.

    .EXAMPLE
        Find-IslSignatureIssue -Context (Get-IslScriptContext -Path .\Detect-App.ps1 -EnforceSignatureCheck)

        The findings this rule produces for one script, as IntuneScriptLab.Finding objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $rule = 'IslSignatureIssue'
    if (-not $Context.EnforceSignatureCheck) { return }
    if ($Context.ScriptType -notin 'Win32Detection', 'Win32Requirement') { return }

    $signature = Get-AuthenticodeSignature -FilePath $Context.Path
    if ($signature.Status -eq 'Valid') { return }

    $phrase = if ($Context.ScriptType -eq 'Win32Detection') { 'detection' } else { 'requirement' }
    $outcome = if ($Context.ScriptType -eq 'Win32Detection') {
        'the app is "not detected", the install runs and the app ends in 0x87D1041C'
    }
    else { 'the requirement is not met (observed for detection rules; assumed for requirement rules)' }
    $findingSplat = @{
        RuleName = $rule
        Severity = 'Error'
        Context  = $Context
        Extent   = $Context.Ast.Extent
        Message  = ("Signature status $($signature.Status): with the signature check enforced the agent " +
            "does not run an unsigned $phrase script at all, and $outcome. Sign the script or turn the " +
            'check off on the rule')
        Evidence = ('Unsigned detection script with enforceSignatureCheck: no probe record, AgentExecutor ' +
            'exit 1, "EnforceSignatureCheck: 1 ... applicationDetected: False", install ran, 0x87D1041C ' +
            '(W32-DET-SIGCHECK)')
    }
    New-IslFinding @findingSplat
}
