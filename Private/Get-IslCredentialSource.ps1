function Get-IslCredentialSource {
    <#
    .SYNOPSIS
    Tells how an expression builds a credential, when it can only ever produce one.

    .DESCRIPTION
    For the interactive-call rule. The expression is recognised when it is the PSCredential
    constructor, New-Object with the PSCredential type, a [pscredential] cast, or Import-Clixml,
    which hands back a credential that Export-Clixml wrote. Parentheses, a pipeline of one element
    and an expression statement around it are looked through. Anything else, a member or another
    call included, gives nothing.

    .PARAMETER Expression
    The syntax tree of the expression.

    .EXAMPLE
    Get-IslCredentialSource -Expression $assignment.Right

    '[pscredential]::new()' for $credential = [pscredential]::new($user, $secure).

    .INPUTS
    None.

    .OUTPUTS
    System.String. How the credential is built, or nothing.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [System.Management.Automation.Language.Ast]$Expression
    )

    $credentialType = '^(System\.Management\.Automation\.)?PSCredential$'
    # Parentheses, a one-element pipeline and the expression statement around a value are wrappers
    $node = $Expression
    $unwrapped = $false
    while ($node -and -not $unwrapped) {
        $kind = $node.GetType().Name
        if ($kind -eq 'ParenExpressionAst') { $node = $node.Pipeline }
        elseif ($kind -eq 'PipelineAst' -and @($node.PipelineElements).Count -eq 1) {
            $node = $node.PipelineElements[0]
        } elseif ($kind -eq 'CommandExpressionAst') { $node = $node.Expression }
        else { $unwrapped = $true }
    }
    if (-not $node) { return }
    switch ($node.GetType().Name) {
        'CommandAst' {
            $commandName = $node.GetCommandName()
            if ($commandName -eq 'Import-Clixml') { return 'Import-Clixml' }
            if ($commandName -ne 'New-Object') { return }
            $typeName = $null
            $elements = @($node.CommandElements | Select-Object -Skip 1)
            for ($index = 0; $index -lt $elements.Count; $index++) {
                $element = $elements[$index]
                if ($element.GetType().Name -eq 'CommandParameterAst') {
                    if (-not 'TypeName'.StartsWith($element.ParameterName, 'OrdinalIgnoreCase')) { continue }
                    if ($element.Argument) { $typeName = $element.Argument.Extent.Text }
                    elseif ($index + 1 -lt $elements.Count) { $typeName = $elements[$index + 1].Extent.Text }
                    break
                }
                $previous = if ($index -gt 0) { $elements[$index - 1] } else { $null }
                $taken = $previous -and $previous.GetType().Name -eq 'CommandParameterAst' -and
                -not $previous.Argument
                if (-not $taken) { $typeName = $element.Extent.Text; break }
            }
            if ("$typeName".Trim('''"') -match $credentialType) { return 'New-Object PSCredential' }
        }
        'InvokeMemberExpressionAst' {
            $onType = $node.Expression.GetType().Name -eq 'TypeExpressionAst' -and
            $node.Expression.TypeName.FullName -match $credentialType
            # A member named by a variable, as in [pscredential]::$m(), has no Value, and the
            # method it calls cannot be known from the script
            $namedMember = $node.Member.GetType().Name -eq 'StringConstantExpressionAst'
            if ($onType -and $namedMember -and $node.Member.Value -eq 'new') {
                return '[pscredential]::new()'
            }
        }
        'ConvertExpressionAst' {
            if ($node.Type.TypeName.FullName -match $credentialType) { return 'a [pscredential] cast' }
        }
    }
}
