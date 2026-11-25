function Test-IslInsideFunction {
    <#
    .SYNOPSIS
        True when the node sits inside a function or a nested script block (so `return` or `exit`
        there doesn't necessarily end the script).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Node
    )
    $parent = $Node.Parent
    while ($parent) {
        if ($parent.GetType().Name -eq 'FunctionDefinitionAst') { return $true }
        # A script block that isn't the script's own root body (e.g. a ForEach-Object block)
        if ($parent.GetType().Name -eq 'ScriptBlockExpressionAst') { return $true }
        $parent = $parent.Parent
    }
    $false
}
