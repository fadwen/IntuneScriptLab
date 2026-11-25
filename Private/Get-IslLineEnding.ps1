function Get-IslLineEnding {
    <#
    .SYNOPSIS
    Tells which line endings a text uses: CRLF, LF, or none for a text of one line.

    .DESCRIPTION
    For Compare-IntuneDeployedScript, which reports a script whose line endings differ from the
    tenant's copy. A text with any CRLF counts as CRLF; one with only LF counts as LF.

    .PARAMETER Text
    The script's text.

    .EXAMPLE
    Get-IslLineEnding -Text "Write-Output 1`r`nexit 0"

    Returns 'CRLF'.

    .INPUTS
    None.

    .OUTPUTS
    System.String. CRLF, LF, or an empty string.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    if ($Text -match "`r`n") {
        'CRLF'
    } elseif ($Text -match "`n") {
        'LF'
    } else {
        ''
    }
}
