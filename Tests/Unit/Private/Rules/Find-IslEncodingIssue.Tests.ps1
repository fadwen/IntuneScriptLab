#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Windows PowerShell 5.1 reads UTF-8 without a BOM as the ANSI code page, so non-ASCII source
    is mangled before it runs; output goes through the OEM code page either way (REM-OUT-UNICODE).
#>

BeforeAll {
    $script:ModuleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
    $script:NonAscii = 'Write-Output "Gr' + [char]0xFC + [char]0xDF + 'e"; exit 0'
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Find-IslEncodingIssue' -Tag 'Unit', 'Private', 'Rule' {

    It 'warns on non-ASCII without a BOM' {
        $path = New-TestScript 'Detect-E.ps1' $script:NonAscii
        $findings = @(Get-RuleFinding $path IslEncodingIssue)
        @($findings | Where-Object Severity -eq 'Warning').Count | Should-Be 1
    }

    It 'does not warn when the BOM is present, but still notes output mangling' {
        $path = New-TestScript 'Detect-E2.ps1' $script:NonAscii -Bom
        $findings = @(Get-RuleFinding $path IslEncodingIssue)
        @($findings | Where-Object Severity -eq 'Warning').Count | Should-Be 0
        @($findings | Where-Object Severity -eq 'Information').Count | Should-Be 1
    }

    It 'is silent for pure ASCII without a BOM' {
        $path = New-TestScript 'Detect-E3.ps1' 'Write-Output "plain"; exit 0'
        @(Get-RuleFinding $path IslEncodingIssue).Count | Should-Be 0
    }

    It 'warns on UTF-16' {
        $path = New-TestScript 'Detect-E4.ps1' 'exit 0' -Utf16
        @(Get-RuleFinding $path IslEncodingIssue).Message | Should-BeLikeString '*UTF-16*'
    }
}
