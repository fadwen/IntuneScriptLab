#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    -Context System for real: a scheduled task registered as NT AUTHORITY\SYSTEM runs the script
    in session 0 from system32, the way the Intune agent does. Skipped unless the session is
    elevated; the refusal path is unit-tested with the task cmdlets mocked.
#>

#pester:no-parallel

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $script:IsAdmin = ([Security.Principal.WindowsPrincipal]$identity).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'SYSTEM context' -Tag 'Integration', 'SystemIntegration', 'Runtime', 'Elevated' {

    It 'runs as NT AUTHORITY\SYSTEM in session 0 from system32' -Skip:(-not $script:IsAdmin) {
        $path = New-TestScript 'who.ps1' ('"$([Security.Principal.WindowsIdentity]::GetCurrent().Name)|' +
            '$((Get-Process -Id $PID).SessionId)|$((Get-Location).Path)|$([Environment]::Is64BitProcess)"') -Bom
        $result = Invoke-IntunePlatformScriptTest -Path $path -Architecture x86 -Context System -TimeoutSeconds 120
        $result.RunState | Should-Be 'Success'
        $who, $session, $cwd, $is64 = $result.StdOut.Trim() -split '\|'
        $who | Should-Be 'NT AUTHORITY\SYSTEM'
        $session | Should-Be '0'
        $cwd | Should-BeLikeString '*\system32'
        $is64 | Should-Be 'False'
    }

    It 'maps the remediation flow as SYSTEM' -Skip:(-not $script:IsAdmin) {
        $marker = Join-Path $TestDrive 'sys.marker'
        $detect = New-TestScript 'Detect.ps1' ("if (Test-Path '$marker') { 'present'; exit 0 } " +
            "else { 'missing'; exit 1 }") -Bom
        $testScriptSplat = @{
            Bom     = $true
            Content = "New-Item -ItemType File -Path '$marker' | Out-Null; exit 0"
        }
        $remediate = New-TestScript 'Remediate.ps1' @testScriptSplat
        $intuneRemediationTestSplat = @{
            DetectionPath   = $detect
            RemediationPath = $remediate
            Architecture    = 'x86'
            Context         = 'System'
            TimeoutSeconds  = 120
        }
        $result = Invoke-IntuneRemediationTest @intuneRemediationTestSplat
        $result.Status | Should-Be 'Fixed'
        $result.IntuneOutput | Should-Be 'missing'
    }

    It 'times out and cleans up the task' -Skip:(-not $script:IsAdmin) {
        $path = New-TestScript 'slow.ps1' 'Start-Sleep -Seconds 60' -Bom
        $result = Invoke-IntunePlatformScriptTest -Path $path -Architecture x86 -Context System -TimeoutSeconds 5
        $result.RunState | Should-Be 'TimedOut'
        @(Get-ScheduledTask -TaskName 'IntuneScriptLab-*' -ErrorAction SilentlyContinue).Count | Should-Be 0
    }
}
