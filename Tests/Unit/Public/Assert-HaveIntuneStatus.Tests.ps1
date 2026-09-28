#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Should-HaveIntuneStatus against fabricated results, checked three ways as the custom-assertion
    guide asks: passes on the right status, fails on the wrong one, and the failure message
    carries the diagnosis with no unexpanded token. Real results are piped in from
    Tests\Integration\PesterAssertions.Tests.ps1.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
    $script:Recurred = [pscustomobject]@{
        PSTypeName   = 'IntuneScriptLab.RemediationResult'
        Status       = 'Recurred'
        IntuneOutput = 'still broken'
        IntuneError  = ''
        Warnings     = @('Detection exited 2: Intune treats any non-zero exit as issue found')
    }
    $script:Installed = [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.Win32AppResult'
        Status     = 'Installed after install'
        Warnings   = @()
    }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Assert-HaveIntuneStatus' -Tag 'Unit', 'Public' {

    Context 'Parameter Validation' {
        It 'is exported under its Should- alias' {
            (Get-Command Should-HaveIntuneStatus).CommandType | Should-Be 'Alias'
            (Get-Command Should-HaveIntuneStatus).ResolvedCommand.Name | Should-Be 'Assert-HaveIntuneStatus'
        }

        It 'takes the expected status by position and the result from the pipeline' {
            $script:Recurred | Should-HaveIntuneStatus 'Recurred'
            Assert-HaveIntuneStatus 'Recurred' $script:Recurred
        }
    }

    Context 'Core Functionality' {
        It 'passes on the matching status for remediation and Win32 results' {
            $script:Recurred | Should-HaveIntuneStatus 'Recurred'
            $script:Installed | Should-HaveIntuneStatus 'Installed after install'
        }

        It 'fails on another status' {
            { $script:Recurred | Should-HaveIntuneStatus 'Fixed' } | Should-Throw
        }
    }

    Context 'Failure message' {
        It 'names the expected and actual status, the reason, output and warnings' {
            $message = Get-AssertionMessage {
                $script:Recurred | Should-HaveIntuneStatus 'Fixed' -Because 'the fix should stick'
            }
            $message | Should-BeLikeString ("Expected status 'Fixed', because the fix should stick, but Intune " +
                "would report 'Recurred'.*")
            $message | Should-BeLikeString '*IntuneOutput: still broken*'
            $message | Should-BeLikeString '*Warnings: Detection exited 2*'
            $message | Should-NotBeLikeString '*<*>*'
        }

        It 'omits the detail when the result carries none' {
            $message = Get-AssertionMessage { $script:Installed | Should-HaveIntuneStatus 'Installed' }
            $message | Should-BeLikeString "*but Intune would report 'Installed after install'.*"
            $message | Should-NotBeLikeString '*IntuneOutput*'
        }
    }
}
