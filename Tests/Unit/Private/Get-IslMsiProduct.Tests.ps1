#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Product code lookup across the registry views Windows Installer writes to. A fake per-user
    product is registered under HKCU for the test and removed afterwards; the per-machine views are
    exercised through whatever the machine has installed, read-only.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force

    $script:Code = '{0D0F9D9B-3F0E-4B2A-9C7B-ISLTEST00001}'
    $script:Key = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$($script:Code)"
    $null = New-Item -Path $script:Key -Force
    Set-ItemProperty -Path $script:Key -Name DisplayName -Value 'IntuneScriptLab Test Product'
    Set-ItemProperty -Path $script:Key -Name DisplayVersion -Value '110.0.2'

    function Get-MsiProduct {
        param([string]$ProductCode)
        InModuleScope IntuneScriptLab -Parameters @{ ProductCode = $ProductCode } {
            Get-IslMsiProduct -ProductCode $ProductCode
        }
    }
}

AfterAll {
    Remove-Item -Path $script:Key -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Get-IslMsiProduct' -Tag 'Unit', 'Private' {

    It 'finds a per-user product with its name and version' {
        $product = Get-MsiProduct $script:Code
        $product | Should-NotBeNull
        $product.DisplayName | Should-Be 'IntuneScriptLab Test Product'
        $product.DisplayVersion | Should-Be '110.0.2'
        $product.View | Should-Be 'HKCU'
        $product.PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.MsiProduct'
    }

    It 'accepts the code without braces' {
        (Get-MsiProduct $script:Code.Trim('{}')).ProductCode | Should-Be $script:Code
    }

    It 'returns nothing for a code that is not installed (W32-MSI-MISSING)' {
        Get-MsiProduct '{00000000-1111-2222-3333-444444444444}' | Should-BeNull
    }
}
