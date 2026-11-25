#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The rule filter of Test-IntuneScript: -IncludeRule, -ExcludeRule and the same keys of a
    settings file.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    function Test-Selected {
        param([hashtable]$Parameters)
        $scope = @{ Parameters = $Parameters }
        InModuleScope IntuneScriptLab -Parameters $scope { Test-IslRuleSelected @Parameters }
    }
}

Describe 'Test-IslRuleSelected' -Tag 'Unit', 'Private' {

    Context 'Parameter Validation' {
        It 'needs a rule name and takes both lists as optional' {
            $command = InModuleScope IntuneScriptLab { Get-Command -Name Test-IslRuleSelected }
            $command | Should-HaveParameter -ParameterName RuleName -Type ([string]) -Mandatory
            $command | Should-HaveParameter -ParameterName Include -Type ([string[]])
            $command | Should-HaveParameter -ParameterName Exclude -Type ([string[]])
        }
    }

    Context 'Core Functionality' {
        It 'returns <Expected> for <Case>' -ForEach @(
            @{ Case = 'no lists'; Include = @(); Exclude = @(); Expected = $true }
            @{ Case = 'an include pattern that matches'; Include = @('IslLong*'); Exclude = @(); Expected = $true }
            @{ Case = 'an include pattern that misses'; Include = @('IslExit*'); Exclude = @(); Expected = $false }
            @{ Case = 'an exclusion by name'; Include = @(); Exclude = @('IslLongSleep'); Expected = $false }
            @{ Case = 'both lists matching'; Include = @('Isl*'); Exclude = @('IslLong*'); Expected = $false }
            @{ Case = 'another letter case'; Include = @('isllongsleep'); Exclude = @(); Expected = $true }
            @{ Case = 'lists of empty entries'; Include = @(''); Exclude = @(''); Expected = $true }
        ) {
            $result = Test-Selected @{ RuleName = 'IslLongSleep'; Include = $Include; Exclude = $Exclude }

            $result | Should-Be $Expected
        }

        It 'returns one Boolean' {
            $result = @(Test-Selected @{ RuleName = 'IslLongSleep' })

            $result | Should-BeCollection -Count 1
            Should-HaveType -Actual $result[0] -Expected ([bool])
        }
    }
}
