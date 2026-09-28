#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Should-PassIntuneAnalysis: a clean script passes as a path and as a FileInfo, a script with
    findings fails and lists them, and the severity and type switches are honoured. Static
    analysis only; nothing runs.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
    $script:Clean = New-TestScript 'Detect-Clean.ps1' ("if (Test-Path 'C:\x') { Write-Output 'ok'; exit 0 } " +
        "else { Write-Output 'missing'; exit 1 }")
    $script:Dirty = New-TestScript 'Detect-Bad.ps1' "Read-Host 'x'`nreturn 1`nexit 1"
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Assert-PassIntuneAnalysis' -Tag 'Unit', 'Public' {

    Context 'Parameter Validation' {
        It 'is exported under its Should- alias' {
            (Get-Command Should-PassIntuneAnalysis).ResolvedCommand.Name | Should-Be 'Assert-PassIntuneAnalysis'
        }

        It 'accepts a path and a FileInfo' {
            $script:Clean | Should-PassIntuneAnalysis
            Get-Item $script:Clean | Should-PassIntuneAnalysis
        }

        It 'limits MinimumSeverity and ScriptType to the analyzer values' {
            $command = Get-Command Assert-PassIntuneAnalysis
            $command.Parameters['MinimumSeverity'].Attributes.ValidValues |
                Should-BeCollection @('Information', 'Warning', 'Error')
            $command.Parameters['ScriptType'].Attributes.ValidValues | Should-ContainCollection 'Win32Detection'
        }
    }

    Context 'Core Functionality' {
        It 'fails a script with findings and lists each one' {
            { $script:Dirty | Should-PassIntuneAnalysis } | Should-Throw
            $message = Get-AssertionMessage {
                $script:Dirty | Should-PassIntuneAnalysis -Because 'it ships to production'
            }
            $message | Should-BeLikeString '*because it ships to production, but got *'
            $message | Should-BeLikeString '*Detect-Bad.ps1:*[[]Error[]] IslInteractiveCall:*'
            $message | Should-BeLikeString '*IslExitCodeIssue*'
            $message | Should-NotBeLikeString '*<*>*'
        }

        It 'never counts the assumed-context note as a finding' {
            # The type is inferred from the name, so the Information note is emitted and must be ignored
            $quiet = New-TestScript 'Detect-Quiet.ps1' "Write-Output 'checked'`nexit 0"
            @(Test-IntuneScript -Path $quiet).RuleName | Should-BeCollection @('IslAssumedContext')
            $quiet | Should-PassIntuneAnalysis -MinimumSeverity Information
        }

        It 'respects the minimum severity and the script type' {
            # exit 2 is only a Warning for a Detection, and no finding at all for a platform script
            $warnOnly = New-TestScript 'Detect-Warn.ps1' 'Write-Output "x"; exit 2'
            { $warnOnly | Should-PassIntuneAnalysis } | Should-Throw
            $warnOnly | Should-PassIntuneAnalysis -MinimumSeverity Error
            $warnOnly | Should-PassIntuneAnalysis -ScriptType PlatformScript
        }
    }
}
