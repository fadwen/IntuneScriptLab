# AST helpers shared by the rules. Type names are compared as strings so the module loads on
# Windows PowerShell 5.1, where the PowerShell 7 node types (ternary, pipeline chain) don't exist.

function Find-IslAstNode {
    <#
    .SYNOPSIS
        Finds AST nodes by type name, optionally filtered by a predicate.
    #>
    [CmdletBinding()]
    # The parameters are used inside the FindAll predicate; the analyzer can't see through it
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Ast,

        # One or more AST class names, e.g. 'CommandAst', 'ExitStatementAst'
        [Parameter(Mandatory)]
        [string[]]$TypeName,

        [scriptblock]$Where
    )
    $Ast.FindAll({
            param($node)
            if ($node.GetType().Name -notin $TypeName) { return $false }
            if ($Where) { return [bool](& $Where $node) }
            $true
        }, $true)
}

function Find-IslCommand {
    <#
    .SYNOPSIS
        Finds command invocations by name (case-insensitive), including aliases the caller lists.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Ast,

        [Parameter(Mandatory)]
        [string[]]$Name
    )
    Find-IslAstNode -Ast $Ast -TypeName CommandAst -Where {
        param($node)
        $commandName = $node.GetCommandName()
        $commandName -and $commandName -in $Name
    }
}

function Test-IslCommandParameter {
    <#
    .SYNOPSIS
        True when the command is called with the named parameter (prefix match, like PowerShell).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.CommandAst]$Command,

        [Parameter(Mandatory)]
        [string]$ParameterName
    )
    foreach ($element in $Command.CommandElements) {
        $isParameter = $element.GetType().Name -eq 'CommandParameterAst'
        if ($isParameter -and $ParameterName.StartsWith($element.ParameterName, 'OrdinalIgnoreCase')) {
            return $true
        }
    }
    $false
}

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

function Test-IslInsideTryWithCatch {
    <#
    .SYNOPSIS
        True when the node is inside the body of a try that has a catch block.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Node
    )
    $child = $Node
    $parent = $Node.Parent
    while ($parent) {
        $isTry = $parent.GetType().Name -eq 'TryStatementAst'
        if ($isTry -and $parent.Body -eq $child -and $parent.CatchClauses.Count -gt 0) {
            return $true
        }
        $child = $parent
        $parent = $parent.Parent
    }
    $false
}

function Get-IslStringLiteral {
    <#
    .SYNOPSIS
        Every string literal in the script (constant and expandable), with its extent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Ast
    )
    Find-IslAstNode -Ast $Ast -TypeName StringConstantExpressionAst, ExpandableStringExpressionAst
}
