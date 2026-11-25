function Find-IslAstNode {
    <#
    .SYNOPSIS
        Finds a syntax tree's nodes by type name, optionally filtered by a predicate.

    .DESCRIPTION
        For the analyzer's rules. The nodes come from the tree's index (Get-IslAstIndex), which
        is built in one walk the first time a tree is asked about. Type names are compared as
        strings, so a node type that only PowerShell 7 has, such as TernaryExpressionAst, finds
        nothing on Windows PowerShell 5.1 instead of failing to resolve. The nodes are in
        document order, also when several types are asked for.

    .PARAMETER Ast
        The syntax tree, or the part of it, to search.

    .PARAMETER TypeName
        One or more AST class names, such as CommandAst or ExitStatementAst.

    .PARAMETER Where
        A script block that is given each node as its first argument; a node is kept when it
        returns a true value. Leave it out to keep every node.

    .EXAMPLE
        Find-IslAstNode -Ast $ast -TypeName ExitStatementAst -Where { param($node) $node.Pipeline }

        Every exit statement of the script that gives an exit code.

    .INPUTS
        None.

    .OUTPUTS
        System.Management.Automation.Language.Ast.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.Language.Ast])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Ast,

        # One or more AST class names, e.g. 'CommandAst', 'ExitStatementAst'
        [Parameter(Mandatory)]
        [string[]]$TypeName,

        [scriptblock]$Where
    )
    $index = Get-IslAstIndex -Ast $Ast
    $nodes = foreach ($name in $TypeName) {
        if ($index.ByType.ContainsKey($name)) { $index.ByType[$name] }
    }
    # Each type's list is in document order; several types are merged back into it
    if ($TypeName.Count -gt 1) { $nodes = $nodes | Sort-Object -Property { $_.Extent.StartOffset } }
    foreach ($node in $nodes) {
        if (-not $Where -or [bool](& $Where $node)) { $node }
    }
}
