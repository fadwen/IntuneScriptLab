function Get-IslVersionPart {
    <#
    .SYNOPSIS
    Splits a version text into four numbers, the way an assignment filter compares versions.

    .DESCRIPTION
    A text of one to four numbers separated by dots, with white space around it allowed, gives
    four numbers, the parts that are missing as 0: '10.0.26100' gives 10, 0, 26100, 0. Any other
    text is not a version, and gives nothing.

    .PARAMETER Text
    The text to read.

    .EXAMPLE
    Get-IslVersionPart -Text '10.0.26100.4202'

    Returns 10, 0, 26100 and 4202.

    .INPUTS
    None.

    .OUTPUTS
    System.Int64. Four numbers, or nothing when the text is not a version.
    #>
    [CmdletBinding()]
    [OutputType([long])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    if ($Text -notmatch '^\s*\d+(\.\d+){0,3}\s*$') {
        return
    }
    $parts = [System.Collections.Generic.List[long]]::new()
    foreach ($part in ($Text.Trim() -split '\.')) { $parts.Add([long]$part) }
    while ($parts.Count -lt 4) { $parts.Add(0) }
    $parts.ToArray()
}
