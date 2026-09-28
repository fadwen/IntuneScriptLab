#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Which powershell.exe the agent launches for an architecture, resolved on this device: x86 is
    SysWOW64 on every 64-bit Windows, the native 64-bit host is System32, and the host the CPU
    lacks (x64 on ARM64, arm64 on x64) is refused rather than silently substituted.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
    $osArchitecture = "$([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)"
    $script:Native = if ($osArchitecture -eq 'Arm64') { 'arm64' } else { 'x64' }
    $script:Missing = if ($script:Native -eq 'arm64') { 'x64' } else { 'arm64' }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Get-IslHostPath' -Tag 'Unit', 'Private' {

    Context 'Parameter Validation' {
        It 'accepts only x86, x64 and arm64' {
            { InModuleScope IntuneScriptLab { Get-IslHostPath -Architecture ia64 } } | Should-Throw
        }
    }

    Context 'Core Functionality' {
        It 'resolves x86 to the SysWOW64 host on a 64-bit device' {
            $result = InModuleScope IntuneScriptLab { Get-IslHostPath -Architecture x86 }
            $result.Path | Should-BeLikeString '*\SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
            $result.Architecture | Should-Be 'x86'
            $result.PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.Host'
            Test-Path $result.Path | Should-BeTrue
        }

        It 'resolves the native 64-bit host to System32' {
            $result = InModuleScope IntuneScriptLab -Parameters @{ Native = $script:Native } {
                Get-IslHostPath -Architecture $Native
            }
            $result.Path | Should-BeLikeString '*\System32\WindowsPowerShell\v1.0\powershell.exe'
            $result.Emulated | Should-BeFalse
        }

        It 'marks x86 as emulated only on ARM64' {
            $result = InModuleScope IntuneScriptLab { Get-IslHostPath -Architecture x86 }
            $result.Emulated | Should-Be ($script:Native -eq 'arm64')
            $expected = "$([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)"
            $result.OSArchitecture | Should-Be $expected
        }
    }

    Context 'Error Handling' {
        It 'refuses the 64-bit host this CPU does not have and names the right one' {
            $failure = { InModuleScope IntuneScriptLab -Parameters @{ Missing = $script:Missing } {
                Get-IslHostPath -Architecture $Missing
            } } | Should-Throw
            $failure.Exception.Message | Should-BeLikeString "*-Architecture $($script:Native)*"
        }
    }
}
