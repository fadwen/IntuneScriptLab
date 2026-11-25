function Test-IslFilterEscapedQuote {
    <#
    .SYNOPSIS
    Tells whether two filter tokens are a double quote someone tried to escape.

    .DESCRIPTION
    For the assignment filter parser. A double quote inside a value has no escape (FLT-V44,
    FLT-V45): "say \"hi\"" tokenizes as a string ending in a backslash with a word glued to it,
    and "say ""hi""" as two strings glued together. Either shape where a connector, a comma or a
    closing parenthesis was expected is that mistake, not a missing 'and'. The tokens are glued
    when the second starts right after the first ends.

    .PARAMETER Previous
    The token before the unexpected one. Nothing gives $false.

    .PARAMETER Next
    The unexpected token. Nothing gives $false.

    .EXAMPLE
    Test-IslFilterEscapedQuote -Previous $parser.Tokens[2] -Next $parser.Tokens[3]

    $true for the tokens "say \" and hi\" of (device.deviceName -eq "say \"hi\"").

    .INPUTS
    None.

    .OUTPUTS
    System.Boolean.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [AllowNull()]
        [psobject]$Previous,

        [Parameter()]
        [AllowNull()]
        [psobject]$Next
    )

    if (-not $Previous -or -not $Next -or $Previous.Type -ne 'string') { return $false }
    $glued = $Next.Position -eq $Previous.End + 1
    [bool]($glued -and ($Next.Type -eq 'string' -or $Previous.Text.EndsWith('\')))
}
