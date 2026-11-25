#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    A warning about a clause, added to the assignment filter parser.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }
}

Describe 'Add-IslFilterWarning' -Tag 'Unit', 'Private' {

    It 'adds a FilterWarning with its kind and message, and writes nothing' {
        $result = InModuleScope IntuneScriptLab {
            $parser = New-IslFilterParser -Rule 'x'
            $output = @(Add-IslFilterWarning -Parser $parser -Kind 'NeverMatches' -Message 'never')
            [pscustomobject]@{ Output = $output; Warnings = $parser.Warnings.ToArray() }
        }

        $result.Output | Should-BeCollection @()
        $result.Warnings | Should-BeCollection -Count 1
        $result.Warnings[0] | Should-HaveType 'IntuneScriptLab.FilterWarning'
        $result.Warnings[0].Kind | Should-Be 'NeverMatches'
        $result.Warnings[0].Message | Should-Be 'never'
    }

    It 'refuses a kind it does not know' {
        {
            InModuleScope IntuneScriptLab {
                Add-IslFilterWarning -Parser (New-IslFilterParser -Rule 'x') -Kind 'Other' -Message 'x'
            }
        } | Should-Throw -FullyQualifiedErrorId 'ParameterArgumentValidationError,*'
    }
}
