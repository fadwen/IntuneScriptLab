#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The result of one requirement that Test-IntuneWin32Requirement checks.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    function Invoke-NewCheck {
        <#
        .SYNOPSIS
            Runs New-IslRequirementCheck inside the module with the given parameters.

        .DESCRIPTION
            New-IslRequirementCheck is private, so the test reaches it through InModuleScope and
            splats the hashtable onto it there.

        .PARAMETER Parameters
            The parameters of New-IslRequirementCheck by name, such as Requirement and Met.

        .EXAMPLE
            Invoke-NewCheck @{ Requirement = 'Architecture'; Met = $true; Actual = 'x64'; Expected = 'x64' }

            Returns the check of an architecture requirement that is met.

        .INPUTS
            None.

        .OUTPUTS
            IntuneScriptLab.RequirementCheck. The result of the requirement.
        #>
        [CmdletBinding()]
        [OutputType('IntuneScriptLab.RequirementCheck')]
        param(
            [hashtable]$Parameters
        )

        $scope = @{ Parameters = $Parameters }
        InModuleScope IntuneScriptLab -Parameters $scope { New-IslRequirementCheck @Parameters }
    }
}

Describe 'New-IslRequirementCheck' -Tag 'Unit', 'Private' {

    Context 'Parameter Validation' {
        It 'needs the name of the requirement and takes Met as a switch' {
            $command = InModuleScope IntuneScriptLab { Get-Command -Name New-IslRequirementCheck }
            $command | Should-HaveParameter -ParameterName Requirement -Type ([string]) -Mandatory
            $command | Should-HaveParameter -ParameterName Met -Type ([switch])
        }
    }

    Context 'Core Functionality' {
        It 'leaves out the details and the code of a requirement that is met' {
            $check = Invoke-NewCheck @{
                Requirement = 'Architecture'; Met = $true; Actual = 'x64'; Expected = 'x64'
                Details = 'not applicable'; Code = 1000
            }

            $check | Should-HaveType 'IntuneScriptLab.RequirementCheck'
            $check.Requirement | Should-Be 'Architecture'
            $check.Met | Should-BeTrue
            $check.Actual | Should-Be 'x64'
            $check.Expected | Should-Be 'x64'
            $check.Details | Should-Be ''
            $check.Applicability | Should-BeNull
        }

        It 'carries the details and the code of a requirement that is not met' {
            $check = Invoke-NewCheck @{
                Requirement = 'Architecture'; Met = $false; Actual = 'arm64'; Expected = 'x64'
                Details = 'not applicable'; Code = 1000
            }

            $check.Met | Should-BeFalse
            $check.Details | Should-Be 'not applicable'
            $check.Applicability | Should-Be 1000
        }

        It 'takes a requirement without a code' {
            $check = Invoke-NewCheck @{ Requirement = 'MinimumWindowsRelease'; Met = $false; Code = $null }

            $check.Met | Should-BeFalse
            $check.Applicability | Should-BeNull
        }
    }
}
