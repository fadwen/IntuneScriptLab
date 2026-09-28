#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The Should- assertions fed by real harness results, the way a user's own suite uses them
    (Examples\IntuneScripts.Tests.ps1.template). The assertion logic itself is unit-tested with
    fabricated results under Tests\Unit\Public.
#>

#pester:no-parallel

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Pester assertions on real results' -Tag 'Integration', 'EndToEnd', 'Runtime' {

    It 'Should-HaveIntuneStatus reads a remediation result and reports its output on failure' {
        $detect = New-TestScript 'Detect.ps1' 'Write-Output "still broken"; exit 1' -Bom
        $remediate = New-TestScript 'Remediate.ps1' 'exit 0' -Bom
        $result = Invoke-IntuneRemediationTest -DetectionPath $detect -RemediationPath $remediate -Architecture x86
        $result | Should-HaveIntuneStatus 'Recurred'
        $message = Get-AssertionMessage { $result | Should-HaveIntuneStatus 'Fixed' }
        $message | Should-BeLikeString "*would report 'Recurred'*IntuneOutput: still broken*"
    }

    It 'Should-BeIntuneDetected and Should-NotBeIntuneDetected read detection results' {
        $intuneDetectionTestSplat = @{
            Architecture = 'x86'
            Path         = (New-TestScript 'yes.ps1' 'Write-Output "installed"; exit 0' -Bom)
        }
        Invoke-IntuneDetectionTest @intuneDetectionTestSplat | Should-BeIntuneDetected
        Invoke-IntuneDetectionTest -Architecture x86 -Path (New-TestScript 'no.ps1' 'exit 0' -Bom) |
            Should-NotBeIntuneDetected
    }

    It 'Should-BeIntuneApplicable and Should-NotBeIntuneApplicable read requirement results' {
        $intuneRequirementTestSplat = @{
            Architecture = 'x86'
            OutputType   = 'String'
            Value        = 'ok'
            Path         = (New-TestScript 'req-ok.ps1' 'Write-Output "ok"' -Bom)
        }
        Invoke-IntuneRequirementTest @intuneRequirementTestSplat | Should-BeIntuneApplicable
        $intuneRequirementTestSplat2 = @{
            Architecture = 'x86'
            OutputType   = 'Integer'
            Operator     = 'GreaterThan'
            Value        = '3'
            Path         = (New-TestScript 'req-bad.ps1' 'Write-Output "five"' -Bom)
        }
        $result = Invoke-IntuneRequirementTest @intuneRequirementTestSplat2
        $result | Should-NotBeIntuneApplicable
        $message = Get-AssertionMessage { $result | Should-BeIntuneApplicable }
        $message | Should-BeLikeString "*not applicable: 'Output 'five' is not an integer*"
    }

    It 'Should-HaveIntuneRunState reads a platform script result and quotes its output on failure' {
        $intunePlatformScriptTestSplat = @{
            Architecture = 'x86'
            Path         = (New-TestScript 'bad.ps1' 'Write-Error "broken"; exit 1' -Bom)
        }
        $result = Invoke-IntunePlatformScriptTest @intunePlatformScriptTestSplat
        $result | Should-HaveIntuneRunState 'Failed'
        $message = Get-AssertionMessage { $result | Should-HaveIntuneRunState 'Success' }
        $message | Should-BeLikeString "*but got 'Failed' (exit 1). Output: *broken*"
    }
}
