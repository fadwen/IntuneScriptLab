#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The path helper for the PSScriptAnalyzer rules, and the shape of the rule module it points at
    (checked without PSScriptAnalyzer, which Tests\Integration\PSScriptAnalyzerRules.Tests.ps1
    covers).
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }
}

Describe 'Get-IntuneAnalyzerRulePath' -Tag 'Unit', 'Public' {

    It 'returns the rule module file inside the installed module' {
        $path = Get-IntuneAnalyzerRulePath
        $path | Should-Be (Join-Path $script:ModuleRoot 'PSScriptAnalyzer\IntuneScriptLab.Rules.psm1')
        Test-Path $path | Should-BeTrue
    }

    It 'ships a rule module that names one Measure- function per rule, and the context note' {
        $source = Get-Content (Get-IntuneAnalyzerRulePath) -Raw
        $source | Should-BeLikeString '*Join-Path -Path $PSScriptRoot -ChildPath *IntuneScriptLab.psd1*'
        $source | Should-BeLikeString '*IslAssumedContext*'
        $source | Should-BeLikeString '*Export-ModuleMember*'
    }

    It 'says where the rule module should be when it is not there' {
        Mock Test-Path -ModuleName IntuneScriptLab { $false }

        $failure = { Get-IntuneAnalyzerRulePath } | Should-Throw
        $failure.FullyQualifiedErrorId | Should-BeLikeString 'AnalyzerRulesMissing,*'
        $failure.Exception.Message | Should-BeLikeString 'The PSScriptAnalyzer rule module is missing*'
    }
}
