#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Rule hashtables in the Graph shape and in the short Type shape map onto the same
    Test-IntuneWin32Rule parameters.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    function Convert-Spec {
        <#
        .SYNOPSIS
            Converts a rule hashtable with ConvertFrom-IslRuleSpec inside the module.

        .DESCRIPTION
            ConvertFrom-IslRuleSpec is private, so the test reaches it through InModuleScope.

        .PARAMETER Rule
            The rule, in the Graph shape or in the short Type shape.

        .EXAMPLE
            Convert-Spec @{ Type = 'ProductCode'; ProductCode = '{1}' }

            Returns the Test-IntuneWin32Rule parameters of a product code rule.

        .INPUTS
            None.

        .OUTPUTS
            System.Collections.Hashtable. The parameters of Test-IntuneWin32Rule.
        #>
        [CmdletBinding()]
        [OutputType([hashtable])]
        param(
            [hashtable]$Rule
        )

        InModuleScope IntuneScriptLab -Parameters @{ Rule = $Rule } { ConvertFrom-IslRuleSpec -Rule $Rule }
    }
}

Describe 'ConvertFrom-IslRuleSpec' -Tag 'Unit', 'Private' {

    It 'maps a Graph file rule' {
        $splat = Convert-Spec @{
            '@odata.type' = '#microsoft.graph.win32LobAppFileSystemRule'; ruleType = 'detection'
            path = '%ProgramFiles%\App'; fileOrFolderName = 'a.exe'; check32BitOn64System = $true
            operationType = 'version'; operator = 'greaterThanOrEqual'; comparisonValue = '9.0'
        }
        $splat.Path | Should-Be '%ProgramFiles%\App'
        $splat.FileOrFolderName | Should-Be 'a.exe'
        $splat.FileOperation | Should-Be 'version'
        $splat.Operator | Should-Be 'greaterThanOrEqual'
        $splat.Value | Should-Be '9.0'
        $splat.Check32BitOn64System | Should-BeTrue
    }

    It 'maps a short registry rule and leaves notConfigured operators out' {
        $splat = Convert-Spec @{
            Type = 'Registry'; KeyPath = 'HKEY_LOCAL_MACHINE\SOFTWARE\X'; OperationType = 'exists'
            Operator = 'notConfigured'
        }
        $splat.KeyPath | Should-Be 'HKEY_LOCAL_MACHINE\SOFTWARE\X'
        $splat.RegistryOperation | Should-Be 'exists'
        $splat.ContainsKey('ValueName') | Should-BeFalse
        $splat.ContainsKey('Operator') | Should-BeFalse
        $splat.ContainsKey('Value') | Should-BeFalse
    }

    It 'maps a product code rule with its own version operator and value' {
        $splat = Convert-Spec @{
            '@odata.type' = '#microsoft.graph.win32LobAppProductCodeRule'; productCode = '{1}'
            productVersionOperator = 'greaterThan'; productVersion = '2.0'
        }
        $splat.ProductCode | Should-Be '{1}'
        $splat.Operator | Should-Be 'greaterThan'
        $splat.Value | Should-Be '2.0'
        (Convert-Spec @{ Type = 'ProductCode'; ProductCode = '{1}' }).ContainsKey('Operator') | Should-BeFalse
    }

    It 'refuses a script rule and an unknown shape' {
        { Convert-Spec @{ '@odata.type' = '#microsoft.graph.win32LobAppPowerShellScriptRule' } } |
            Should-Throw -FullyQualifiedErrorId 'RuleIsScript,*' -ExceptionMessage '*Invoke-IntuneDetectionTest*'
        { Convert-Spec @{ Path = 'C:\x' } } |
            Should-Throw -FullyQualifiedErrorId 'RuleTypeUnknown,*' -ExceptionMessage '*Type of File, Registry*'
    }
}
