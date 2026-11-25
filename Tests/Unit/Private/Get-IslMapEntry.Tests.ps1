#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The -Map entry of Compare-IntuneDeployedScript for a tenant policy, by display name or id.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }

    function script:Get-Entry {
        param([hashtable]$Map, [hashtable]$Matched)
        InModuleScope IntuneScriptLab -Parameters @{ Map = $Map; Matched = $Matched } {
            Get-IslMapEntry -Policy @{ id = 'p1'; displayName = 'Detect-Printer' } -Map $Map -Matched $Matched
        }
    }
}

Describe 'Get-IslMapEntry' -Tag 'Unit', 'Private' {

    It 'gives the entry whose key is the policy''s <Case>, and records the key' -ForEach @(
        @{ Case = 'display name'; Key = 'Detect-Printer' }
        @{ Case = 'id'; Key = 'p1' }
    ) {
        $matched = @{}
        $entry = Get-Entry -Map @{ $Key = 'printer.ps1'; 'Other' = 'other.ps1' } -Matched $matched

        $entry | Should-Be 'printer.ps1'
        $matched.Keys | Should-BeCollection @($Key)
    }

    It 'gives nothing for a policy without a key, or without a map' {
        $matched = @{}

        Get-Entry -Map @{ 'Other' = 'other.ps1' } -Matched $matched | Should-BeCollection @()
        Get-Entry -Map $null -Matched $matched | Should-BeCollection @()
        $matched.Count | Should-Be 0
    }
}
