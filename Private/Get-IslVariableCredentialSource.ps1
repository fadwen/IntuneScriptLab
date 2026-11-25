function Get-IslVariableCredentialSource {
    <#
    .SYNOPSIS
    Tells how a variable holds a credential, when every value given to it is one.

    .DESCRIPTION
    For the interactive-call rule. Every assignment to the variable anywhere in the script, with
    or without a scope prefix, must build a credential as Get-IslCredentialSource recognises it or
    be typed [pscredential], and a parameter of that name must be typed [pscredential]. The result
    names each distinct way, joined by commas. When the script never gives the variable a value,
    or any one of its values could be something else, the function gives nothing.

    .PARAMETER Variable
    The variable, as it is used in the call.

    .PARAMETER Ast
    The syntax tree of the whole script, where the assignments and parameters are looked for.

    .EXAMPLE
    Get-IslVariableCredentialSource -Variable $handed -Ast $Context.Ast

    'Import-Clixml' for a $credential that the script assigns only from Import-Clixml.

    .INPUTS
    None.

    .OUTPUTS
    System.String. How the credential is built, or nothing.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.VariableExpressionAst]$Variable,

        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Ast
    )

    $credentialType = '^(System\.Management\.Automation\.)?PSCredential$'
    $scopePrefix = '^(script|local|private|global):'
    $variableName = $Variable.VariablePath.UserPath -replace $scopePrefix, ''
    $sources = [System.Collections.Generic.List[string]]::new()
    $assignments = Find-IslAstNode -Ast $Ast -TypeName AssignmentStatementAst -Where {
        param($node)
        $target = $node.Left
        $wrapped = $target.GetType().Name -in 'ConvertExpressionAst', 'AttributedExpressionAst'
        if ($wrapped) { $target = $target.Child }
        $target.GetType().Name -eq 'VariableExpressionAst' -and
        ($target.VariablePath.UserPath -replace $scopePrefix, '') -eq $variableName
    }
    foreach ($assignment in $assignments) {
        $typed = $assignment.Left.GetType().Name -eq 'ConvertExpressionAst' -and
            $assignment.Left.Type.TypeName.FullName -match $credentialType
        $source = if ($typed) { 'a [pscredential] variable' }
        else { Get-IslCredentialSource -Expression $assignment.Right }
        if (-not $source) { return }
        $sources.Add($source)
    }
    $parameters = Find-IslAstNode -Ast $Ast -TypeName ParameterAst -Where {
        param($node)
        $node.Name.VariablePath.UserPath -eq $variableName
    }
    foreach ($parameter in $parameters) {
        $typed = @($parameter.Attributes | Where-Object {
                $_.GetType().Name -eq 'TypeConstraintAst' -and $_.TypeName.FullName -match $credentialType
            }).Count -gt 0
        if (-not $typed) { return }
        $sources.Add('a [pscredential] parameter')
    }
    if ($sources.Count) { @($sources | Select-Object -Unique) -join ', ' }
}
