function Read-IslFilterPrimary {
    <#
    .SYNOPSIS
    Reads a clause or a parenthesized expression of an assignment filter rule.

    .DESCRIPTION
    For the assignment filter parser. At the parser's cursor, an opening parenthesis starts an
    expression that Read-IslFilterExpression reads and that must end with the matching closing
    parenthesis; anything else is a clause for Read-IslFilterClause. A parenthesis that is not
    closed, a closing parenthesis where a clause belongs, and an escaped double quote before the
    closing parenthesis (Test-IslFilterEscapedQuote) each record the reason in the parser.

    .PARAMETER Parser
    The parser state from New-IslFilterParser.

    .EXAMPLE
    Read-IslFilterPrimary -Parser $parser

    The Clause node of (device.deviceName -eq "X"), with the cursor past the closing parenthesis.

    .INPUTS
    None.

    .OUTPUTS
    System.Collections.Hashtable. A Clause, And or Or node, or nothing when the rule does not
    parse.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Parser
    )

    $token = Get-IslFilterToken -Parser $Parser
    if (-not $token) {
        Add-IslFilterParseError -Parser $Parser -Message 'expected a clause or "(" at the end of the rule'
        return
    }
    if ($token.Type -eq 'rparen') {
        Add-IslFilterParseError -Parser $Parser -Message "unexpected ')' at position $($token.Position)"
        return
    }
    if ($token.Type -ne 'lparen') { return Read-IslFilterClause -Parser $Parser }

    $Parser.Pos++
    $inner = Read-IslFilterExpression -Parser $Parser
    if ($Parser.Error) { return }
    $close = Get-IslFilterToken -Parser $Parser
    if (-not $close) {
        Add-IslFilterParseError -Parser $Parser -Message "the '(' at position $($token.Position) is not closed"
        return
    }
    if ($close.Type -ne 'rparen') {
        $previous = $Parser.Tokens[$Parser.Pos - 1]
        if (Test-IslFilterEscapedQuote -Previous $previous -Next $close) {
            Add-IslFilterEscapeError -Parser $Parser -Previous $previous
        } else {
            Add-IslFilterParseError -Parser $Parser -Message (
                "expected 'and', 'or' or ')' at position $($close.Position), found '$($close.Text)'")
        }
        return
    }
    $Parser.Pos++
    $inner
}
