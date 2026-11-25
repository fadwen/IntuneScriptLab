function Get-IslFilterToken {
    <#
    .SYNOPSIS
    Gets the assignment filter token at the parser's cursor.

    .DESCRIPTION
    For the assignment filter parser. Returns the token at the parser's Pos, an object with Type,
    Text, Position and End, or nothing when the cursor is past the last token. The cursor does
    not move.

    .PARAMETER Parser
    The parser state from New-IslFilterParser.

    .EXAMPLE
    Get-IslFilterToken -Parser $parser

    The lparen token at position 1 for a parser of (device.deviceName -eq "X") that has not
    read anything yet.

    .INPUTS
    None.

    .OUTPUTS
    IntuneScriptLab.FilterToken. The token, or nothing at the end of the rule.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.FilterToken')]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Parser
    )

    if ($Parser.Pos -lt $Parser.Tokens.Count) { $Parser.Tokens[$Parser.Pos] }
}
