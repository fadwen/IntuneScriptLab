#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    SYSTEM has no user hive, profile or mapped drives (REM-CTX-SYSTEM); a user-context script
    cannot write HKLM or control services.
#>

BeforeAll {
    $script:ModuleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Find-IslContextIssue' -Tag 'Unit', 'Private', 'Rule' {

    It 'errors on HKCU and user profile variables in SYSTEM context' {
        $path = New-TestScript 'Detect-U.ps1' "Get-ItemProperty 'HKCU:\Software\X'`n`$p = `$env:APPDATA`nexit 0"
        $findings = @(Get-RuleFinding $path IslContextIssue @{ Context = 'System' })
        @($findings | Where-Object Severity -eq 'Error').Count | Should-Be 2
    }

    It 'warns on mapped drive letters in SYSTEM context' {
        $path = New-TestScript 'Detect-D.ps1' "Copy-Item 'H:\file' 'C:\x'; exit 0"
        $findings = @(Get-RuleFinding $path IslContextIssue @{ Context = 'System' })
        @($findings | Where-Object Message -like '*not mapped*').Count | Should-Be 1
    }

    It 'warns on HKLM writes and service control in user context' {
        $path = New-TestScript 'script.ps1' ("Set-ItemProperty 'HKLM:\SOFTWARE\X' -Name a -Value 1`n" +
            'Restart-Service Spooler')
        $findings = @(Get-RuleFinding $path IslContextIssue @{ Context = 'User' })
        @($findings | Where-Object Severity -eq 'Warning').Count | Should-Be 2
    }

    It 'is silent about HKCU in user context' {
        $path = New-TestScript 'script.ps1' "Get-ItemProperty 'HKCU:\Software\X'"
        $findings = @(Get-RuleFinding $path IslContextIssue @{ Context = 'User' })
        @($findings | Where-Object Severity -ne 'Information').Count | Should-Be 0
    }

    It 'notes once that user context is skipped on Entra-registered devices' {
        $path = New-TestScript 'script.ps1' "Write-Output 'hello'"
        $findings = @(Get-RuleFinding $path IslContextIssue @{ Context = 'User' })
        $findings.Count | Should-Be 1
        $findings[0].Severity | Should-Be 'Information'
        $findings[0].Message | Should-BeLikeString '*Entra-registered device*skips it*'
        $findings[0].Line | Should-Be 0
    }

    It 'does not add the join-type note for Win32 requirement scripts, which do run there' {
        $path = New-TestScript 'App-Requirement.ps1' "Write-Output 'yes'"
        @(Get-RuleFinding $path IslContextIssue @{ Context = 'User' }).Count | Should-Be 0
    }
}
