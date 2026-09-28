function Find-IslScriptSize {
    <#
    .SYNOPSIS
        Flags scripts over the documented 200 KB, and over the size the service actually refuses.

    .DESCRIPTION
        Microsoft Learn puts the limit for remediation and platform scripts at 200 KB. The service
        takes more than that: through the Graph API a remediation of 504 KB and a platform script
        of 660 KB were accepted, while 512 KB and 680 KB were refused with a generic error, and a
        250 KB remediation and a 500 KB platform script ran on the device (REM-SIZE-250KB,
        PS-SIZE-500KB). A script over the documented limit is therefore reported as a warning,
        because the portal and other tooling may hold to it; a script over what the API refused is
        an error, because it cannot be deployed.

    .PARAMETER Context
        The IntuneScriptLab.ScriptContext from Get-IslScriptContext: AST, tokens, bytes and the
        effective ScriptType, Context and Architecture.

    .EXAMPLE
        Find-IslScriptSize -Context (Get-IslScriptContext -Path .\Detect.ps1)

        The findings this rule produces for one script, as IntuneScriptLab.Finding objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $rule = 'IslScriptSize'
    $bytes = $Context.Bytes.Length
    if ($bytes -le 200KB) { return }
    $kind = if ($Context.ScriptType -eq 'PlatformScript') { 'platform script' } else { 'remediation' }
    # The largest sizes the API accepted and the smallest it refused, per type (round 7)
    $accepted = if ($kind -eq 'platform script') { 660KB } else { 504KB }
    $refused = if ($kind -eq 'platform script') { 680KB } else { 512KB }
    $evidence = ('Microsoft Learn: "must be less than 200 KB"; the Graph API accepted a 504 KB remediation ' +
        'and a 660 KB platform script and refused 512 KB and 680 KB; a 250 KB remediation and a 500 KB ' +
        'platform script ran on the device (REM-SIZE-250KB, PS-SIZE-500KB)')
    $sizeKB = [math]::Round($bytes / 1KB)

    if ($bytes -ge $refused) {
        $findingSplat = @{
            RuleName = $rule
            Severity = 'Error'
            Context  = $Context
            Extent   = $Context.Ast.Extent
            Message  = ("The file is $sizeKB KB; the service refused a $kind of $([int]($refused / 1KB)) KB, " +
                'so this one cannot be uploaded. Split it or move the bulk into content the script downloads')
            Evidence = $evidence
        }
    }
    else {
        $findingSplat = @{
            RuleName = $rule
            Severity = 'Warning'
            Context  = $Context
            Extent   = $Context.Ast.Extent
            Message  = ("The file is $sizeKB KB, over the documented 200 KB limit. The API took a $kind of " +
                "up to $([int]($accepted / 1KB)) KB and the device ran one this size, but the portal and " +
                'other tooling may hold to 200 KB')
            Evidence = $evidence
        }
    }
    New-IslFinding @findingSplat
}
