#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Should-NotBeIntuneDetected against fabricated detection results: passes when not detected,
    fails otherwise, and the failure message quotes the exit code and stdout that counted as
    installed.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
    $script:Detected = [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.DetectionResult'
        Detected   = $true
        Reason     = 'Exit 0 with stdout and no stderr'
        ExitCode   = 0
        StdOut     = "installed`r`n"
    }
    $script:Missed = [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.DetectionResult'
        Detected   = $false
        Reason     = 'Exit code 1: only exit 0 can mean installed'
        ExitCode   = 1
        StdOut     = ''
    }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Assert-NotBeIntuneDetected' -Tag 'Unit', 'Public' {

    Context 'Parameter Validation' {
        It 'is exported under its Should- alias' {
            (Get-Command Should-NotBeIntuneDetected).ResolvedCommand.Name | Should-Be 'Assert-NotBeIntuneDetected'
        }
    }

    Context 'Core Functionality' {
        It 'passes on a missed result' {
            $script:Missed | Should-NotBeIntuneDetected
        }

        It 'fails on a detected result' {
            { $script:Detected | Should-NotBeIntuneDetected } | Should-Throw
        }
    }

    Context 'Failure message' {
        It 'quotes the exit code and trimmed stdout that counted as installed' {
            $message = Get-AssertionMessage {
                $script:Detected | Should-NotBeIntuneDetected -Because 'the app is absent'
            }
            $message | Should-BeLikeString ('Expected the app not to be detected, because the app is absent, ' +
                "but exit 0 with stdout 'installed' counts as installed.*")
            $message | Should-NotBeLikeString '*<*>*'
        }
    }
}
