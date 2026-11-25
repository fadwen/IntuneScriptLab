#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Whether the assignment filter token at the parser's cursor is and or or.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }

    function script:Test-Next {
        param([string]$Rule, [string]$Name)
        InModuleScope IntuneScriptLab -Parameters @{ Rule = $Rule; Name = $Name } {
            Test-IslFilterConnector -Parser (New-IslFilterParser -Rule $Rule) -Name $Name
        }
    }
}

Describe 'Test-IslFilterConnector' -Tag 'Unit', 'Private' {

    It 'gives <Expected> for <Rule> and <Name>' -ForEach @(
        @{ Rule = 'and'; Name = 'and'; Expected = $true }
        @{ Rule = '-AND'; Name = 'and'; Expected = $true }
        @{ Rule = '-or'; Name = 'or'; Expected = $true }
        @{ Rule = 'or'; Name = 'and'; Expected = $false }
        @{ Rule = '"and"'; Name = 'and'; Expected = $false }
        @{ Rule = 'android'; Name = 'and'; Expected = $false }
        @{ Rule = ''; Name = 'and'; Expected = $false }
    ) {
        Test-Next -Rule $Rule -Name $Name | Should-Be $Expected
    }
}
