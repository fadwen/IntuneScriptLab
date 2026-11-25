#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The order of two versions in an assignment filter.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    function script:Compare-Pair {
        <#
        .SYNOPSIS
            Compares two version texts with the module's private Compare-IslFilterVersion.

        .DESCRIPTION
            Runs Compare-IslFilterVersion inside the module, where the private function is visible,
            and returns what it gave as an array, so that a test can count an order that is missing.

        .PARAMETER Actual
            The version text of the device.

        .PARAMETER Expected
            The version text of the filter rule.

        .EXAMPLE
            Compare-Pair -Actual '10.0.26100' -Expected '10.0.22631'

            Returns 1, because the device version is the later one.

        .INPUTS
            None.

        .OUTPUTS
            System.Int32. -1, 0 or 1, or nothing when either text is not a version.
        #>
        [CmdletBinding()]
        [OutputType([int])]
        param(
            [string]$Actual,

            [string]$Expected
        )

        InModuleScope IntuneScriptLab -Parameters @{ Actual = $Actual; Expected = $Expected } {
            @(Compare-IslFilterVersion -Actual $Actual -Expected $Expected)
        }
    }
}

Describe 'Compare-IslFilterVersion' -Tag 'Unit', 'Private' {

    It 'orders <Actual> against <Expected> as <Order>' -ForEach @(
        @{ Actual = '10.0.26100'; Expected = '10.0.22631'; Order = 1 }
        @{ Actual = '10.0.9'; Expected = '10.0.10'; Order = -1 }
        @{ Actual = '10.0'; Expected = '10.0.0.0'; Order = 0 }
        @{ Actual = '10.0.26100.4202'; Expected = '10.0.26100.4203'; Order = -1 }
    ) {
        $result = Compare-Pair -Actual $Actual -Expected $Expected

        $result | Should-BeCollection -Count 1
        $result[0] | Should-Be $Order
    }

    It 'gives no order when <Case>' -ForEach @(
        @{ Case = 'the device value is not a version'; Actual = 'unknown'; Expected = '10.0' }
        @{ Case = 'the rule value is not a version'; Actual = '10.0'; Expected = 'Windows 11' }
        @{ Case = 'the device has no value'; Actual = ''; Expected = '10.0' }
    ) {
        Compare-Pair -Actual $Actual -Expected $Expected | Should-BeCollection @()
    }
}
