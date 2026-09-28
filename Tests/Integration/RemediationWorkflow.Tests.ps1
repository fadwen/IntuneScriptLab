#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The detect, remediate, detect flow end to end with real Windows PowerShell processes and a
    marker file the remediation creates: the statuses the portal shows for Fixed, Recurred,
    Failed and Without issues.
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

Describe 'Remediation workflow' -Tag 'Integration', 'EndToEnd', 'Runtime' {

    It 'reports Without issues and skips the remediation when detection exits 0' {
        $detect = New-TestScript 'Detect.ps1' 'Write-Output "fine"; exit 0' -Bom
        $marker = Join-Path $TestDrive 'ran.txt'
        $testScriptSplat = @{
            Bom     = $true
            Content = "New-Item -ItemType File -Path '$marker' | Out-Null; exit 0"
        }
        $remediate = New-TestScript 'Remediate.ps1' @testScriptSplat
        $result = Invoke-IntuneRemediationTest -DetectionPath $detect -RemediationPath $remediate -Architecture x86
        $result.Status | Should-Be 'Without issues'
        $result.Remediation | Should-BeNull
        Test-Path $marker | Should-BeFalse
        $result.IntuneOutput | Should-Be 'fine'
    }

    It 'reports Fixed when the remediation makes the post-detection pass' {
        $marker = Join-Path $TestDrive 'fixed.marker'
        $detect = New-TestScript 'Detect.ps1' ("if (Test-Path '$marker') { 'present'; exit 0 } " +
            "else { 'missing'; exit 1 }") -Bom
        $remediate = New-TestScript 'Remediate.ps1' ("New-Item -ItemType File -Path '$marker' | Out-Null; " +
            "'created'; exit 0") -Bom
        $result = Invoke-IntuneRemediationTest -DetectionPath $detect -RemediationPath $remediate -Architecture x86
        $result.Status | Should-Be 'Fixed'
        $result.IntuneOutput | Should-Be 'missing'
        $result.PostOutput | Should-Be 'present'
        $result.RemediationOutput | Should-Be 'created'
        $result.PreDetection.Host | Should-BeLikeString '*\SysWOW64\*'
    }

    It 'reports Recurred when the remediation exits 0 but detection still fails, on any non-zero exit code' {
        $detect = New-TestScript 'Detect.ps1' 'Write-Output "still broken"; exit 2' -Bom
        $remediate = New-TestScript 'Remediate.ps1' 'exit 0' -Bom
        $result = Invoke-IntuneRemediationTest -DetectionPath $detect -RemediationPath $remediate -Architecture x86
        $result.Status | Should-Be 'Recurred'
        $result.Warnings -join ' ' | Should-BeLikeString '*exited 2*'
    }

    It 'reports Failed and skips the post-detection when the remediation exits non-zero' {
        $detect = New-TestScript 'Detect.ps1' 'exit 1' -Bom
        $remediate = New-TestScript 'Remediate.ps1' 'Write-Error "nope"; exit 1' -Bom
        $result = Invoke-IntuneRemediationTest -DetectionPath $detect -RemediationPath $remediate -Architecture x86
        $result.Status | Should-Be 'Failed'
        $result.PostDetection | Should-BeNull
        $result.Remediation.StdErr | Should-BeLikeString '*nope*'
    }
}
