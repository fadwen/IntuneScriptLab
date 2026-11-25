#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The local candidates for one script rule of a Win32 app.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    function script:Select-Candidate {
        <#
        .SYNOPSIS
            Selects the candidates of one script rule with Select-IslRuleCandidate.

        .DESCRIPTION
            Runs the module's private Select-IslRuleCandidate inside the module and returns the
            candidates it gave for the rule as an array.

        .PARAMETER Candidate
            The local candidates found for the app's script rules.

        .PARAMETER RuleCount
            The number of script rules the app has.

        .PARAMETER Index
            The index of the rule the candidates are selected for.

        .EXAMPLE
            Select-Candidate -Candidate @('a', 'b') -RuleCount 2 -Index 1

            Returns 'b', the candidate at the rule's own index.

        .INPUTS
            None.

        .OUTPUTS
            System.Object. Each candidate selected for the rule.
        #>
        [CmdletBinding()]
        [OutputType([object])]
        param(
            [object[]]$Candidate,

            [int]$RuleCount,

            [int]$Index
        )

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
