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
