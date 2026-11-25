function Add-IslFilterParseError {
    <#
    .SYNOPSIS
    Records why an assignment filter rule does not parse, unless a reason is already recorded.

    .DESCRIPTION
    For the assignment filter parser. The first failure is the one reported, so a message is
    kept only when the parser has none yet; it is stored with the prefix "Filter rule: ". Every
    Read-IslFilter* function tests the parser's Error after a call and stops when it is set.

    .PARAMETER Parser
    The parser state from New-IslFilterParser.

    .PARAMETER Message
    Why the rule does not parse, such as "the rule is empty".

    .EXAMPLE
    Add-IslFilterParseError -Parser $parser -Message 'the rule is empty'

    Sets $parser.Error to "Filter rule: the rule is empty", when it was not set before.

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
        [string]$Message
    )

    if (-not $Parser.Error) { $Parser.Error = "Filter rule: $Message" }
}
