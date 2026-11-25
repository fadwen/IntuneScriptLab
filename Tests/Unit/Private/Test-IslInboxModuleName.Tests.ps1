#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Whether a module name a script uses is in-box under the agent, for the module-dependency rule.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    function script:Test-Name {
        <#
        .SYNOPSIS
            Tests a module name with the module's private Test-IslInboxModuleName.

        .DESCRIPTION
            Runs Test-IslInboxModuleName inside the module against a fixed in-box list of
            Microsoft.PowerShell.Utility and Storage, so that the cases do not depend on the modules
            this computer has.

        .PARAMETER Name
            The module name as the script uses it.

        .EXAMPLE
            Test-Name -Name 'storage'

            Returns True, because the name is in the list in another letter case.

        .INPUTS
            None.

        .OUTPUTS
            System.Boolean. Whether the name counts as in-box.
        #>
        [CmdletBinding()]
        [OutputType([bool])]
        param(
            [string]$Name
        )

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
