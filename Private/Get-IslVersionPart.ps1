function Get-IslVersionPart {
    <#
    .SYNOPSIS
    Splits a version text into four numbers, the way an assignment filter compares versions.

    .DESCRIPTION
    A text of one to four numbers separated by dots, with white space around it allowed, gives
    four numbers, the parts that are missing as 0: '10.0.26100' gives 10, 0, 26100, 0. Any other
    text is not a version, and gives nothing; so does a text with a part too large for a 64-bit
    number, which has no order the comparison could use.

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
    foreach ($part in ($Text.Trim() -split '\.')) {
        $number = [long]0
        $style = [System.Globalization.NumberStyles]::None
        if (-not [long]::TryParse($part, $style, [cultureinfo]::InvariantCulture, [ref]$number)) {
            return
        }
        $parts.Add($number)
    }
    while ($parts.Count -lt 4) { $parts.Add(0) }
    $parts.ToArray()
}
