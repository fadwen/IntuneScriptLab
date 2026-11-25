#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The lines of a script without the blank lines at its end.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }
}

Describe 'Get-IslTrimmedLine' -Tag 'Unit', 'Private' {

    It 'leaves out the blank lines at the end only' {
        $lines = @(InModuleScope IntuneScriptLab { Get-IslTrimmedLine -Line @('a', '', 'b', '', '') })

        $lines | Should-BeCollection -Count 3
        $lines[0] | Should-Be 'a'
        $lines[1] | Should-Be ''
        $lines[2] | Should-Be 'b'
    }

    It 'gives a single line as one string, which a caller wraps in @()' {
        $output = InModuleScope IntuneScriptLab { Get-IslTrimmedLine -Line @('only', '') }

        # Unwrapped it is a string, which has no Count under strict mode
        Should-HaveType -Actual $output -Expected ([string])
        $output | Should-Be 'only'
        @($output) | Should-BeCollection -Count 1
    }

    It 'gives nothing when every line is blank' {
        InModuleScope IntuneScriptLab { Get-IslTrimmedLine -Line @('', '') } | Should-BeCollection @()
    }
}
