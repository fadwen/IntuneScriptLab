#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The default architecture of the Win32 harness commands: the 64-bit host this device has,
    which Get-IslHostPath resolves to System32 rather than refusing.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    $osArchitecture = "$([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)"
    $script:Native = if ($osArchitecture -eq 'Arm64') { 'arm64' } else { 'x64' }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Get-IslHostArchitecture' -Tag 'Unit', 'Private' {

    It 'names the 64-bit host this device has' {
        InModuleScope IntuneScriptLab { Get-IslHostArchitecture } | Should-Be $script:Native
    }

    It 'names a host Get-IslHostPath resolves instead of refusing' {
        $hostInfo = InModuleScope IntuneScriptLab { Get-IslHostPath -Architecture (Get-IslHostArchitecture) }
        $hostInfo.Path | Should-BeLikeString '*\WindowsPowerShell\v1.0\powershell.exe'
        $hostInfo.Path | Should-NotBeLikeString '*SysWOW64*'
    }
}
