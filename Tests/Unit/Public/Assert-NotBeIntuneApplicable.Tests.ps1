#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Should-NotBeIntuneApplicable against fabricated requirement results: passes when the rule is
    not met, fails otherwise, and the failure message quotes the output that met it.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
    $script:Met = [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.RequirementResult'
        Applicable = $true
        Reason     = "Output 'ok' meets String Equal 'ok'"
    }
    $script:Unmet = [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.RequirementResult'
        Applicable = $false
        Reason     = 'Exit code 1: the output is only evaluated on exit 0, so the rule fails'
    }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Assert-NotBeIntuneApplicable' -Tag 'Unit', 'Public' {

    Context 'Parameter Validation' {
        It 'is exported under its Should- alias' {
            (Get-Command Should-NotBeIntuneApplicable).ResolvedCommand.Name |
                Should-Be 'Assert-NotBeIntuneApplicable'
        }
    }

    Context 'Core Functionality' {
        It 'passes when the rule is not met' {
            $script:Unmet | Should-NotBeIntuneApplicable
        }

        It 'fails when the rule is met' {
            { $script:Met | Should-NotBeIntuneApplicable } | Should-Throw
        }
    }

    Context 'Failure message' {
        It 'quotes the output that met the rule' {
            $message = Get-AssertionMessage {
                $script:Met | Should-NotBeIntuneApplicable -Because 'the prerequisite is absent here'
            }
            $message | Should-BeLikeString ('Expected the requirement not to be met, because the prerequisite ' +
                "is absent here, but 'Output 'ok' meets String Equal 'ok''*")
            $message | Should-NotBeLikeString '*<*>*'
        }
    }
}
