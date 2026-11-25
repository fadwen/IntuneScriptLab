#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    No function of the module writes to one of its own parameters (STY-16). After such a write
    the variable no longer holds what the caller passed: a later read, a splat of
    $PSBoundParameters or a message that names the parameter then tells two values apart that
    look like one. Read from the syntax trees, because behaviour does not show it.
#>

BeforeDiscovery {
    $moduleRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $folders = 'Public', 'Private'
    $script:Files = foreach ($folder in $folders) {
        $folderPath = Join-Path -Path $moduleRoot -ChildPath $folder
        foreach ($file in Get-ChildItem -LiteralPath $folderPath -Recurse -Filter '*.ps1') {
            @{ Name = $file.BaseName; File = $file.FullName }
        }
    }
}

BeforeAll {
    function script:Get-ReassignedParameter {
        <#
        .SYNOPSIS
        Lists every write to a function's own parameter in a syntax tree.

        .DESCRIPTION
        A write is an assignment, a foreach loop variable, or ++ and -- in either position. The
        parameters are those of the param block and those of the function's signature. A write
        inside a nested function belongs to that function and is checked against its own
        parameters only, so a local of a nested helper that shares a name with a parameter of the
        function around it is not reported.

        .PARAMETER Ast
        The syntax tree of a file.

        .EXAMPLE
        Get-ReassignedParameter -Ast $ast

        Returns lines such as 'Get-Thing line 12: $Path'.

        .INPUTS
        None.

        .OUTPUTS
        System.String. The function, the line and the parameter of each write.
        #>
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [Parameter(Mandatory)]
            [System.Management.Automation.Language.Ast]$Ast
        )

        $language = 'System.Management.Automation.Language'
        $functionType = "$language.FunctionDefinitionAst" -as [type]
        $incrementKinds = 'PlusPlus', 'MinusMinus', 'PostfixPlusPlus', 'PostfixMinusMinus'
        foreach ($function in $Ast.FindAll({ param($node) $node -is $functionType }, $true)) {
            $parameters = @(
                if ($function.Body.ParamBlock) { $function.Body.ParamBlock.Parameters }
                if ($function.Parameters) { $function.Parameters }
            ) | ForEach-Object { $_.Name.VariablePath.UserPath }

            $writes = $function.Body.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.AssignmentStatementAst] -or
                    $node -is [System.Management.Automation.Language.ForEachStatementAst] -or
                    ($node -is [System.Management.Automation.Language.UnaryExpressionAst] -and
                    "$($node.TokenKind)" -in $incrementKinds)
                }, $true)
            foreach ($write in $writes) {
                $owner = $write.Parent
                while ($owner -and $owner -isnot $functionType) {
                    $owner = $owner.Parent
                }
                if ($owner -ne $function) {
                    continue
                }

                $target = switch ($write) {
                    { $_ -is [System.Management.Automation.Language.AssignmentStatementAst] } { $_.Left }
                    { $_ -is [System.Management.Automation.Language.ForEachStatementAst] } { $_.Variable }
                    default { $_.Child }
                }
                if ($target -is [System.Management.Automation.Language.ConvertExpressionAst]) {
                    $target = $target.Child
                }
                $isVariable = $target -is [System.Management.Automation.Language.VariableExpressionAst]
                if ($isVariable -and $target.VariablePath.UserPath -in $parameters) {
                    '{0} line {1}: ${2}' -f $function.Name, $write.Extent.StartLineNumber,
                    $target.VariablePath.UserPath
                }
            }
        }
    }
}

Describe 'Parameter reuse' -Tag 'Unit', 'Contract' {

    It '<Name> writes to none of its parameters' -ForEach $script:Files {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($File, [ref]$null, [ref]$null)
        $reassigned = Get-ReassignedParameter -Ast $ast

        @($reassigned) | Should-BeCollection @()
    }

    It 'finds every kind of write to a parameter, and none that belongs to a nested function' {
        $sample = @'
function Test-Sample {
    param($Path, $Count, $Name, [string]$Mode)
    $Path = 'other'
    [int]$Count = 2
    foreach ($Name in 'a', 'b') { }
    $Mode++
    function Test-Nested {
        param($Other)
        $Path = 'a local of the nested function'
    }
}
function Test-Signature($Value) {
    --$Value
}
'@
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($sample, [ref]$null, [ref]$null)
        $reassigned = @(Get-ReassignedParameter -Ast $ast)

        $reassigned | Should-BeCollection -Count 5
        $reassigned[0] | Should-Be 'Test-Sample line 3: $Path'
        $reassigned[1] | Should-Be 'Test-Sample line 4: $Count'
        $reassigned[2] | Should-Be 'Test-Sample line 5: $Name'
        $reassigned[3] | Should-Be 'Test-Sample line 6: $Mode'
        $reassigned[4] | Should-Be 'Test-Signature line 13: $Value'
    }
}
