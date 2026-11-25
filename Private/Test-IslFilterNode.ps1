function Test-IslFilterNode {
    <#
    .SYNOPSIS
    Tells whether a node of a parsed assignment filter rule matches the facts of a device.

    .DESCRIPTION
    The node is one element of the tree that ConvertFrom-IslFilterRule builds: a Clause, or an
    And or an Or of a Left and a Right node. A clause is tested with Test-IslFilterClause. Both
    sides of And and Or are always tested, without stopping at the first that decides, so that
    every clause of the rule records what it saw.

    .PARAMETER Node
    The node, a hashtable with Type, and Clause or Left and Right.

    .PARAMETER Facts
    The device's facts, by property name. The lookup ignores letter case only when the caller
    builds the dictionary with [System.StringComparer]::OrdinalIgnoreCase, as
    Test-IntuneAssignmentFilter does; with the default comparer, a property written in another
    case is not found and compares as an empty text.

    .EXAMPLE
    Test-IslFilterNode -Node $parsed.Tree -Facts $facts

    $true when the whole rule matches the device.

    .INPUTS
    None.

    .OUTPUTS
    System.Boolean.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Node,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.Dictionary[string, object]]$Facts
    )

    switch ($Node['Type']) {
        'Clause' { Test-IslFilterClause -Clause $Node['Clause'] -Facts $Facts }
        'And' {
            # Both sides run so every clause reports what it saw
            $left = Test-IslFilterNode -Node $Node['Left'] -Facts $Facts
            $right = Test-IslFilterNode -Node $Node['Right'] -Facts $Facts
            $left -and $right
        }
        'Or' {
            $left = Test-IslFilterNode -Node $Node['Left'] -Facts $Facts
            $right = Test-IslFilterNode -Node $Node['Right'] -Facts $Facts
            $left -or $right
        }
    }
}
