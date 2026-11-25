#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Whether the assignment filter token at the parser's cursor is and or or.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    function script:Test-Next {
        <#
        .SYNOPSIS
            Tests whether the token at the start of a filter rule is a given connector.

        .DESCRIPTION
            Builds a parser for the rule, whose cursor starts at its first token, and calls
            Test-IslFilterConnector on it inside the module.

        .PARAMETER Rule
            The text of the assignment filter rule.

        .PARAMETER Name
            The connector to test for, and or or.

        .EXAMPLE
            Test-Next -Rule '-AND' -Name 'and'

            Returns $true.

        .INPUTS
            None.

        .OUTPUTS
            System.Boolean. What Test-IslFilterConnector returns.
        #>
        [CmdletBinding()]
        [OutputType([bool])]
        param(
            [string]$Rule,

            [string]$Name
        )

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
