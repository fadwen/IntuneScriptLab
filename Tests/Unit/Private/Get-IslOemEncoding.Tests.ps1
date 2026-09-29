#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The OEM code page a console-less powershell.exe writes in, read from the registry because
    CultureInfo reports code page 1 under invariant globalization on PowerShell 7.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Get-IslOemEncoding' -Tag 'Unit', 'Private' {

    Context 'Core Functionality' {
        It 'returns the encoding for the OEMCP value in the registry' {
            $key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage'
            $expected = [int](Get-ItemProperty -Path $key -Name OEMCP).OEMCP
            $encoding = InModuleScope IntuneScriptLab { Get-IslOemEncoding }
            ($encoding -is [System.Text.Encoding]) | Should-BeTrue
            $encoding.CodePage | Should-Be $expected
        }

        It 'returns the ANSI code page from ACP with -Kind ANSI' {
            $key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage'
            $expected = [int](Get-ItemProperty -Path $key -Name ACP).ACP
            (InModuleScope IntuneScriptLab { Get-IslOemEncoding -Kind ANSI }).CodePage | Should-Be $expected
        }

        It 'is a real code page, not code page 1' {
            (InModuleScope IntuneScriptLab { Get-IslOemEncoding }).CodePage | Should-BeGreaterThan 1
        }
    }

    Context 'Error Handling' {
        It 'falls back to code page 437 when the registry cannot be read' {
            Mock Get-ItemProperty -ModuleName IntuneScriptLab { throw 'no registry' }
            $encoding = InModuleScope IntuneScriptLab { Get-IslOemEncoding }
            $encoding.CodePage | Should-Be 437
        }
    }
}
