#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Whether a module name a script uses is in-box under the agent, for the module-dependency rule.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }

    # The syntax tree of a script given as text
    function script:ConvertTo-Ast {
        param([string]$Text)
        [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null)
    }

    function script:Test-Name {
        param([string]$Name)
        InModuleScope IntuneScriptLab -Parameters @{ Name = $Name } {
            Test-IslInboxModuleName -Name $Name -InboxModule 'Microsoft.PowerShell.Utility', 'Storage'
        }
    }
}

Describe 'Test-IslInboxModuleName' -Tag 'Unit', 'Private' {

    It 'gives <Expected> for <Name>' -ForEach @(
        @{ Name = 'Storage'; Expected = $true }
        @{ Name = 'storage'; Expected = $true }
        @{ Name = 'Microsoft.Graph.Authentication'; Expected = $false }
        @{ Name = '.\Helpers\Tools.psm1'; Expected = $true }
        @{ Name = 'Tools.psd1'; Expected = $true }
        @{ Name = 'Az.*'; Expected = $true }
        @{ Name = '$moduleName'; Expected = $true }
    ) {
        Test-Name -Name $Name | Should-Be $Expected
    }
}
