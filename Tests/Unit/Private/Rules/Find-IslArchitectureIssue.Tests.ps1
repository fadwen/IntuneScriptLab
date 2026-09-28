#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The 32-bit host is redirected: HKLM:\SOFTWARE reads WOW6432Node, Program Files and System32
    become their 32-bit twins (PS-PROBE-ARCH). ARM64 is a native 64-bit host with no redirection,
    and Sysnative exists only inside a 32-bit process.
#>

BeforeAll {
    $script:ModuleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Find-IslArchitectureIssue' -Tag 'Unit', 'Private', 'Rule' {

    It 'warns on HKLM:\SOFTWARE, Program Files and System32 in the 32-bit host' {
        $path = New-TestScript 'Detect-A.ps1' ("Get-ItemProperty 'HKLM:\SOFTWARE\Vendor\App'`n" +
            "Test-Path 'C:\Program Files\App\app.exe'`n& 'C:\Windows\System32\tool.exe'`nexit 0")
        $findings = @(Get-RuleFinding $path IslArchitectureIssue @{ Architecture = 'x86' })
        $findings.Count | Should-Be 3
        $findings.Severity | Should-All { $_ -eq 'Warning' }
    }

    It 'downgrades to Information when the script checks bitness' {
        $path = New-TestScript 'Detect-B.ps1' ("if (-not [Environment]::Is64BitProcess) { exit 0 }`n" +
            "Get-ItemProperty 'HKLM:\SOFTWARE\Vendor'`nexit 0")
        @(Get-RuleFinding $path IslArchitectureIssue @{ Architecture = 'x86' }).Severity |
            Should-All { $_ -eq 'Information' }
    }

    It 'ignores WOW6432Node and is silent in the 64-bit host' {
        $path = New-TestScript 'Detect-W.ps1' "Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Vendor'; exit 0"
        @(Get-RuleFinding $path IslArchitectureIssue @{ Architecture = 'x86' }).Count | Should-Be 0
        $path2 = New-TestScript 'Detect-W2.ps1' "Get-ItemProperty 'HKLM:\SOFTWARE\Vendor'; exit 0"
        @(Get-RuleFinding $path2 IslArchitectureIssue @{ Architecture = 'x64' }).Count | Should-Be 0
    }

    It 'warns on Sysnative in the 64-bit host, on x64 and on arm64 alike' {
        $path = New-TestScript 'Detect-S.ps1' "& 'C:\Windows\Sysnative\tool.exe'; exit 0"
        @(Get-RuleFinding $path IslArchitectureIssue @{ Architecture = 'x64' }).Count | Should-Be 1
        @(Get-RuleFinding $path IslArchitectureIssue @{ Architecture = 'arm64' }).Count | Should-Be 1
    }

    It 'treats arm64 as a native 64-bit host: no WOW64 redirection findings' {
        $path = New-TestScript 'Detect-W3.ps1' ("Get-ItemProperty 'HKLM:\SOFTWARE\Vendor'; " +
            "Test-Path 'C:\Program Files\App'; exit 0")
        @(Get-RuleFinding $path IslArchitectureIssue @{ Architecture = 'arm64' }).Count | Should-Be 0
    }
}
