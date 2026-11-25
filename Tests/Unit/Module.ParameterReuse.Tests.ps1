#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    No function of the module assigns to one of its own parameters (STY-16). After such an
    assignment the variable no longer holds what the caller passed: a later read, a splat of
    $PSBoundParameters or a message that names the parameter then tells two values apart that
    look like one. Read from the syntax trees, because behaviour does not show it.
#>

BeforeDiscovery {
    $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $folders = 'Public', 'Private'
    $script:Files = foreach ($folder in $folders) {
        foreach ($file in Get-ChildItem -LiteralPath (Join-Path $moduleRoot $folder) -Recurse -Filter '*.ps1') {
            @{ Name = $file.BaseName; File = $file.FullName }
        }
    }
}

Describe 'Parameter reuse' -Tag 'Unit', 'Contract' {

    It '<Name> assigns to none of its parameters' -ForEach $script:Files {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($File, [ref]$null, [ref]$null)
        $isFunction = { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }
        $isAssignment = { param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst] }
        $reassigned = foreach ($function in $ast.FindAll($isFunction, $true)) {
            $parameters = @(if ($function.Body.ParamBlock) {
                    $function.Body.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }
                })
            foreach ($assignment in $function.Body.FindAll($isAssignment, $true)) {
                $target = $assignment.Left
                if ($target -is [System.Management.Automation.Language.ConvertExpressionAst]) {
                    $target = $target.Child
                }
                $isVariable = $target -is [System.Management.Automation.Language.VariableExpressionAst]
                if ($isVariable -and $target.VariablePath.UserPath -in $parameters) {
                    '{0} line {1}: ${2}' -f $function.Name, $assignment.Extent.StartLineNumber,
                    $target.VariablePath.UserPath
                }
            }
        }

        @($reassigned) | Should-BeCollection @()
    }
}
