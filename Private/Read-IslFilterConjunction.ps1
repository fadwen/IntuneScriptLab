function Read-IslFilterConjunction {
    <#
    .SYNOPSIS
    Reads the clauses of an assignment filter rule that are joined by and.

    .DESCRIPTION
    For the assignment filter parser. Reads one primary (Read-IslFilterPrimary), then another for
    each and or -and that follows, and joins them from the left into And nodes, so that and binds
    tighter than or. A failure in any primary ends the read with nothing.

    .PARAMETER Parser
    The parser state from New-IslFilterParser.

    .EXAMPLE
    Read-IslFilterConjunction -Parser $parser

    @{ Type = 'And'; Left = <clause 1>; Right = <clause 2> } for two clauses joined by and.

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

    $left = Read-IslFilterPrimary -Parser $Parser
    if ($Parser.Error) { return }
    while (Test-IslFilterConnector -Parser $Parser -Name 'and') {
        $Parser.Pos++
        $right = Read-IslFilterPrimary -Parser $Parser
        if ($Parser.Error) { return }
        $left = @{ Type = 'And'; Left = $left; Right = $right }
    }
    $left
}
