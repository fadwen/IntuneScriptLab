#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Should-BeIntuneDetected against fabricated detection results: passes on Detected, fails
    otherwise, and the failure message carries the reason Intune would give.
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
        StdOut     = 'installed'
    }
    $script:Missed = [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.DetectionResult'
        Detected   = $false
        Reason     = 'Nothing on stdout: exit 0 alone is "not detected"'
        ExitCode   = 0
        StdOut     = ''
    }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Assert-BeIntuneDetected' -Tag 'Unit', 'Public' {

    Context 'Parameter Validation' {
        It 'is exported under its Should- alias' {
            (Get-Command Should-BeIntuneDetected).ResolvedCommand.Name | Should-Be 'Assert-BeIntuneDetected'
        }

        It 'takes the result from the pipeline or by position' {
            $script:Detected | Should-BeIntuneDetected
            Assert-BeIntuneDetected $script:Detected
        }
    }

    Context 'Core Functionality' {
        It 'passes on a detected result' {
            $script:Detected | Should-BeIntuneDetected
        }

        It 'fails on a missed result' {
            { $script:Missed | Should-BeIntuneDetected } | Should-Throw
        }
    }

    Context 'Failure message' {
        It 'explains the miss with the reason Intune would give' {
            $message = Get-AssertionMessage {
                $script:Missed | Should-BeIntuneDetected -Because 'it was installed'
            }
            $message | Should-BeLikeString ('Expected the app to be detected, because it was installed, but ' +
                "Intune would report not detected: 'Nothing on stdout*")
            $message | Should-NotBeLikeString '*<*>*'
        }
    }
}
