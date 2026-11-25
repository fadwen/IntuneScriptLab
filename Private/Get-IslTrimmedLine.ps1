function Get-IslTrimmedLine {
    <#
    .SYNOPSIS
    Gets the lines of a script without the blank lines at its end.

    .DESCRIPTION
    For Compare-IntuneDeployedScript, which compares two scripts without counting blank lines
    at the end as a difference in content. Each line is written to the pipeline, so a caller that
    reads .Count or an index wraps the call in @(): a single line otherwise arrives as a string.

    .PARAMETER Line
    The script's lines, in order.

    .EXAMPLE
    @(Get-IslTrimmedLine -Line @('Write-Output 1', 'exit 0', '', ''))

    The first two lines.

    .INPUTS
    None.

    .OUTPUTS
    System.String. Each line, or nothing when every line is blank.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Line
    )

    $count = $Line.Count
    while ($count -gt 0 -and -not $Line[$count - 1]) { $count-- }
    if ($count -gt 0) { $Line[0..($count - 1)] }
}
