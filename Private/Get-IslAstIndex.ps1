# AST helpers shared by the rules. Type names are compared as strings so the module loads on
# Windows PowerShell 5.1, where the PowerShell 7 node types (ternary, pipeline chain) don't exist.

# One walk per tree, shared by every rule that asks about it: the nodes grouped by type name and
# the commands grouped by name. Fifteen rules each walking the tree, some of them once per command
# name they look for, was most of the time an analysis took. The table is keyed on the AST object
# itself, so a sub-tree a caller passes gets an index of its own and a tree that goes out of scope
# takes its index with it.
$script:IslAstIndex = [System.Runtime.CompilerServices.ConditionalWeakTable[object, object]]::new()

# The walk and the grouping stay in .NET: FindAll calls its predicate once per node, and a script
# block there costs more than the walk itself; BlockingCollection.TryAdd is a Func<Ast, bool> that
# is always true and keeps the nodes in the order they were visited. Object.GetType as an open
# delegate is the key selector for Enumerable.ToLookup, which keeps each group in source order.
$script:IslAstNodeType = [System.Management.Automation.Language.Ast]
$script:IslAstCollectorType =
    [System.Collections.Concurrent.BlockingCollection[System.Management.Automation.Language.Ast]]
$script:IslAstGetType = [System.Delegate]::CreateDelegate(
    [System.Func[System.Management.Automation.Language.Ast, type]], [object].GetMethod('GetType'))
$script:IslAstToLookup = ([System.Linq.Enumerable].GetMethods() |
        Where-Object { $_.Name -eq 'ToLookup' -and $_.GetParameters().Count -eq 2 } |
        Select-Object -First 1).MakeGenericMethod($script:IslAstNodeType, [type])

function Get-IslAstIndex {
    <#
    .SYNOPSIS
        The node and command index of an AST, built on first use and kept for the tree's lifetime.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.AstIndex')]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Ast
    )
    $index = $null
    if ($script:IslAstIndex.TryGetValue($Ast, [ref]$index)) { return $index }

    # FindAll visits the tree in document order, the root first, and that order is what the groups keep
    $collector = $script:IslAstCollectorType::new()
    $collect = [System.Delegate]::CreateDelegate([System.Func[System.Management.Automation.Language.Ast, bool]],
        $collector, $script:IslAstCollectorType.GetMethod('TryAdd', [type[]]@($script:IslAstNodeType)))
    $null = $Ast.FindAll($collect, $true)
    $lookup = $script:IslAstToLookup.Invoke($null, @([object]$collector.ToArray(), $script:IslAstGetType))

    # Keyed by the type's short name, the way the rules ask: a 7-only node type is a key that is
    # never there on 5.1, not a type that fails to resolve
    $byType = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($group in $lookup) { $byType[$group.Key.Name] = $group }
    $byCommand = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[object]]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    if ($byType.ContainsKey('CommandAst')) {
        foreach ($command in $byType['CommandAst']) {
            # A command whose name is not a constant (& $tool, "$prefix-Item") has no name to index
            $commandName = $command.GetCommandName()
            if (-not $commandName) { continue }
            if (-not $byCommand.ContainsKey($commandName)) {
                $byCommand[$commandName] = [System.Collections.Generic.List[object]]::new()
            }
            $byCommand[$commandName].Add($command)
        }
    }
    $index = [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.AstIndex'
        ByType     = $byType
        ByCommand  = $byCommand
    }
    $script:IslAstIndex.Add($Ast, $index)
    $index
}
