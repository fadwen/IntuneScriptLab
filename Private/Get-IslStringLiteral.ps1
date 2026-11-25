function Get-IslStringLiteral {
    <#
    .SYNOPSIS
        Gets every string literal of a syntax tree, constant and expandable.

    .DESCRIPTION
        For the analyzer's rules that read what a script writes in its strings, such as paths,
        registry keys and text outside ASCII. Each literal is a StringConstantExpressionAst or
        an ExpandableStringExpressionAst, with its extent, in document order.

    .PARAMETER Ast
        The syntax tree, or the part of it, to search.

    .EXAMPLE
        Get-IslStringLiteral -Ast $ast | ForEach-Object { $_.Extent.Text }

        The text of every string in the script, quotes included.

    .INPUTS
        None.

    .OUTPUTS
        System.Management.Automation.Language.ExpressionAst.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.Language.ExpressionAst])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Ast
    )
    Find-IslAstNode -Ast $Ast -TypeName StringConstantExpressionAst, ExpandableStringExpressionAst
}
