#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Whether the Pester that is loaded can carry the module's assertions.
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

Describe 'Test-IslPesterAssertionSupport' -Tag 'Unit', 'Private' {

    It 'gives nothing with Pester 6.2 or later loaded' {
        $output = InModuleScope IntuneScriptLab { @(Test-IslPesterAssertionSupport -ErrorAction Stop) }

        $output | Should-BeCollection @()
    }

    It 'ends with PesterAssertionNotSupported when New-ShouldAssertion is not there' {
        Mock Get-Command -ModuleName IntuneScriptLab -ParameterFilter { $Name -eq 'New-ShouldAssertion' } { }

        { InModuleScope IntuneScriptLab { Test-IslPesterAssertionSupport } } |
            Should-Throw -FullyQualifiedErrorId 'PesterAssertionNotSupported*' -ExceptionMessage '*Pester 6.2*'
    }
}
