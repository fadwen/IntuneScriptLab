#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Should-BeIntuneApplicable against fabricated requirement results: passes when the rule is met,
    fails otherwise, and the failure message carries the reason the agent would give.
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
        Reason     = "Output 'five' is not an integer, so the rule fails"
    }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Assert-BeIntuneApplicable' -Tag 'Unit', 'Public' {

    Context 'Parameter Validation' {
        It 'is exported under its Should- alias' {
            (Get-Command Should-BeIntuneApplicable).ResolvedCommand.Name | Should-Be 'Assert-BeIntuneApplicable'
        }

        It 'takes the result from the pipeline or by position' {
            $script:Met | Should-BeIntuneApplicable
            Assert-BeIntuneApplicable $script:Met
        }
    }

    Context 'Core Functionality' {
        It 'passes when the rule is met' {
            $script:Met | Should-BeIntuneApplicable
        }

        It 'fails when the rule is not met' {
            { $script:Unmet | Should-BeIntuneApplicable } | Should-Throw
        }
    }

    Context 'Failure message' {
        It 'quotes the reason the agent would give' {
            $message = Get-AssertionMessage {
                $script:Unmet | Should-BeIntuneApplicable -Because 'the agent reports its version'
            }
            $message | Should-BeLikeString ('Expected the requirement to be met, because the agent reports its ' +
                "version, but Intune would report not applicable: 'Output 'five' is not an integer*")
            $message | Should-NotBeLikeString '*<*>*'
        }
    }
}
