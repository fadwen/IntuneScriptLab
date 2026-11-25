#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The local candidates for one script rule of a Win32 app.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }

    function script:Select-Candidate {
        param([object[]]$Candidate, [int]$RuleCount, [int]$Index)
        $scope = @{ Candidate = $Candidate; RuleCount = $RuleCount; Index = $Index }
        InModuleScope IntuneScriptLab -Parameters $scope {
            @(Select-IslRuleCandidate -Candidate $Candidate -RuleCount $RuleCount -Index $Index)
        }
    }
}

Describe 'Select-IslRuleCandidate' -Tag 'Unit', 'Private' {

    It 'pairs rule <Index> with candidate <Index> when the counts are the same' -ForEach @(
        @{ Index = 0; Expected = 'a' }
        @{ Index = 1; Expected = 'b' }
    ) {
        Select-Candidate -Candidate @('a', 'b') -RuleCount 2 -Index $Index | Should-BeCollection @($Expected)
    }

    It 'gives the first rule every candidate when the counts differ, and the others none' {
        @(Select-Candidate -Candidate @('a', 'b', 'c') -RuleCount 2 -Index 0) | Should-BeCollection -Count 3
        Select-Candidate -Candidate @('a', 'b', 'c') -RuleCount 2 -Index 1 | Should-BeCollection @()
    }

    It 'gives nothing when there is no candidate' {
        Select-Candidate -Candidate @() -RuleCount 1 -Index 0 | Should-BeCollection @()
    }
}
