function Find-IslAstNode {
    <#
    .SYNOPSIS
        Finds AST nodes by type name, optionally filtered by a predicate.
    #>
    [CmdletBinding()]
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
