#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    On Windows on ARM PROCESSOR_ARCHITECTURE is ARM64, x64 packages run emulated or not at all,
    and there is a third Program Files (Arm) folder (ARM64 survey in Validation\Findings.md).
#>

BeforeAll {
    $script:ModuleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Find-IslArm64Assumption' -Tag 'Unit', 'Private', 'Rule' {

    It 'warns on AMD64 comparisons and notes x64 packages and the missing Program Files (Arm)' {
        $path = New-TestScript 'Detect-Arm.ps1' ("if (`$env:PROCESSOR_ARCHITECTURE -eq 'AMD64') { " +
            "`$url = 'https://x/agent-x64.msi' }`nTest-Path 'C:\Program Files (x86)\App'`nexit 0")
        $findings = @(Get-RuleFinding $path IslArm64Assumption @{ Architecture = 'arm64' })
        @($findings | Where-Object { $_.Severity -eq 'Warning' -and $_.Message -like '*AMD64*' }).Count |
            Should-Be 1
        @($findings | Where-Object Message -like '*x64-specific package*').Count | Should-Be 1
        @($findings | Where-Object Message -like '*Program Files (Arm)*').Count | Should-Be 1
    }

    It 'is silent when the script already handles ARM64' {
        $path = New-TestScript 'Detect-Arm2.ps1' ("if (`$env:PROCESSOR_ARCHITECTURE -match 'ARM64|AMD64') " +
            "{ 'ok' }`n" +
            "Test-Path 'C:\Program Files (x86)\App'; Test-Path `${env:ProgramFiles(Arm)}`nexit 0")
        @(Get-RuleFinding $path IslArm64Assumption @{ Architecture = 'arm64' }).Count | Should-Be 0
    }

    It 'is silent for other architectures' {
        $path = New-TestScript 'Detect-Arm3.ps1' "if (`$env:PROCESSOR_ARCHITECTURE -eq 'AMD64') { 'x64' }`nexit 0"
        @(Get-RuleFinding $path IslArm64Assumption @{ Architecture = 'x64' }).Count | Should-Be 0
        @(Get-RuleFinding $path IslArm64Assumption @{ Architecture = 'x86' }).Count | Should-Be 0
    }
}
