#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The -Map entry of Compare-IntuneDeployedScript for a tenant policy, by display name or id.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    function script:Get-Entry {
        <#
        .SYNOPSIS
            Gets the -Map entry for the policy Detect-Printer with id p1.

        .DESCRIPTION
            Calls the private Get-IslMapEntry inside the module for one fixed policy, so that the
            tests vary only the map and read back the keys it recorded as matched.

        .PARAMETER Map
            The -Map of Compare-IntuneDeployedScript, or $null for none.

        .PARAMETER Matched
            The collection of matched keys that Get-IslMapEntry adds to.

        .EXAMPLE
            Get-Entry -Map @{ 'Detect-Printer' = 'printer.ps1' } -Matched $matched

            Returns 'printer.ps1' and records the key Detect-Printer in $matched.

        .INPUTS
            None.

        .OUTPUTS
            System.Object. The entry, a path or a hashtable of paths by role, or nothing.
        #>
        [CmdletBinding()]
        [OutputType([object])]
        param(
            [hashtable]$Map,

            [hashtable]$Matched
        )

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
