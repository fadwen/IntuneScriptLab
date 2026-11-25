function Get-IslLineExcerpt {
    <#
    .SYNOPSIS
    Shortens a line of a script for a drift message.

    .DESCRIPTION
    For Compare-IntuneDeployedScript, which quotes the first line where two scripts differ. The
    line is trimmed, and a line longer than 60 characters is cut to 57 and ends with three dots.

    .PARAMETER Line
    The line to quote.

    .EXAMPLE
    Get-IslLineExcerpt -Line '    exit 1'

    Returns 'exit 1'.

    .INPUTS
    None.

    .OUTPUTS
    System.String.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Line
    )

    $trimmed = $Line.Trim()
    if ($trimmed.Length -gt 60) { $trimmed.Substring(0, 57) + '...' } else { $trimmed }
}
