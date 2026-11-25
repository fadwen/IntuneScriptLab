function Read-IslFilterExpression {
    <#
    .SYNOPSIS
    Reads an assignment filter expression: groups of clauses joined by or.

    .DESCRIPTION
    For the assignment filter parser. Reads one conjunction (Read-IslFilterConjunction), then
    another for each or or -or that follows, and joins them from the left into Or nodes. It is the
    entry point of the parser, and Read-IslFilterPrimary calls it again for each parenthesized
    expression. A failure anywhere ends the read with nothing.

    .PARAMETER Parser
    The parser state from New-IslFilterParser.

    .EXAMPLE
    Read-IslFilterExpression -Parser (New-IslFilterParser -Rule '(device.deviceName -eq "X")')

    The Clause node of the rule's one clause.

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

    $left = Read-IslFilterConjunction -Parser $Parser
    if ($Parser.Error) { return }
    while (Test-IslFilterConnector -Parser $Parser -Name 'or') {
        $Parser.Pos++
        $right = Read-IslFilterConjunction -Parser $Parser
        if ($Parser.Error) { return }
        $left = @{ Type = 'Or'; Left = $left; Right = $right }
    }
    $left
}
