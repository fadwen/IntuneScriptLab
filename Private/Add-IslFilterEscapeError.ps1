function Add-IslFilterEscapeError {
    <#
    .SYNOPSIS
    Records that a filter rule tries to escape a double quote inside a value.

    .DESCRIPTION
    For the assignment filter parser, once Test-IslFilterEscapedQuote has found the mistake. The
    message says that the service refuses both \" and "" inside a value (FLT-V44, FLT-V45), names
    the position of the value, and suggests matching the parts around the quote. It is recorded
    through Add-IslFilterParseError, so an earlier failure is kept.

    .PARAMETER Parser
    The parser state from New-IslFilterParser.

    .PARAMETER Previous
    The string token that the quote was meant to continue.

    .EXAMPLE
    Add-IslFilterEscapeError -Parser $parser -Previous $parser.Tokens[2]

    Sets $parser.Error to the escaped-quote failure for the value at that token's position.

    .INPUTS
    None.

    .OUTPUTS
    None.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Parser,

        [Parameter(Mandatory)]
        [psobject]$Previous
    )

    $message = ("a double quote inside a value cannot be escaped: the service refuses both \`" and `"`" " +
        "(the value at position $($Previous.Position)); match the parts around the quote with " +
        '-contains or -startsWith instead')
    Add-IslFilterParseError -Parser $Parser -Message $message
}
