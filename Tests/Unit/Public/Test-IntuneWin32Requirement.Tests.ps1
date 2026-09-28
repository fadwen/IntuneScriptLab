#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The base requirement checks with the device facts mocked, each verdict and message a round-6
    observation (Validation\Findings.md, "Win32 requirements, filters, install context and
    relationships").
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Test-IntuneWin32Requirement' -Tag 'Unit', 'Public' {

    BeforeEach {
        # An x64 Windows 11 24H2 device with 60 GB free, 8 GB of RAM, 4 processors at 2.4 GHz
        Mock Get-IslDeviceFact -ModuleName IntuneScriptLab {
            [pscustomobject]@{
                Architecture = 'x64'; Build = 26100; FreeDiskSpaceMB = 61440; MemoryMB = 8192
                Processors = 4; CpuSpeedMHz = 2400
            }
        }
    }

    Context 'Parameter Validation' {
        It 'limits the architectures and the release names' {
            $command = Get-Command Test-IntuneWin32Requirement
            $command.Parameters['Architecture'].Attributes.ValidValues |
                Should-BeCollection @('x86', 'x64', 'arm64')
            $command.Parameters['MinimumWindowsRelease'].Attributes.ValidValues |
                Should-ContainCollection 'Windows11_24H2'
        }

        It 'rejects a zero or negative minimum' {
            { Test-IntuneWin32Requirement -MinimumMemoryMB 0 } | Should-Throw
            { Test-IntuneWin32Requirement -MinimumProcessors -1 } | Should-Throw
        }
    }

    Context 'Core Functionality' {
        It 'is applicable with no requirements, and with every requirement met (W32-REQ-OS-24H2)' {
            $none = Test-IntuneWin32Requirement
            $none.Applicable | Should-BeTrue
            $none.Applicability | Should-Be 0
            $none.PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.ApplicabilityResult'
            $intuneWin32RequirementSplat = @{
                Architecture           = 'x64', 'arm64'
                MinimumWindowsRelease  = 'Windows11_24H2'
                MinimumFreeDiskSpaceMB = 1024
                MinimumMemoryMB        = 4096
                MinimumProcessors      = 2
                MinimumCpuSpeedMHz     = 1000
            }
            $all = Test-IntuneWin32Requirement @intuneWin32RequirementSplat
            $all.Applicable | Should-BeTrue
            @($all.Checks).Count | Should-Be 6
            $all.Checks.Met | Should-All { $_ }
            $all.Reason | Should-BeLikeString 'Every requirement is met (6 checked)*'
        }

        It 'reports the architecture message and code 1000 (W32-REQ-ARCH-ARM64)' {
            $result = Test-IntuneWin32Requirement -Architecture arm64
            $result.Applicable | Should-BeFalse
            $result.Details |
                Should-Be 'Device architecture (e.g. x86/amd64) is not applicable for the application.'
            $result.Applicability | Should-Be 1000
            $result.Checks[0].Actual | Should-Be 'x64'
        }

        It 'reports disk, memory and processor shortfalls with their codes: <Name> is <Code>' -ForEach @(
            @{ Name = 'MinimumFreeDiskSpaceMB'; Value = 100000000; Code = 1001; Text = 'Available disk space*' }
            @{ Name = 'MinimumMemoryMB';        Value = 1000000;   Code = 1003; Text = 'Amount of RAM*' }
            @{ Name = 'MinimumProcessors';      Value = 64;        Code = 1004; Text = 'Count of logical*' }
        ) {
            $splat = @{ $Name = $Value }
            $result = Test-IntuneWin32Requirement @splat
            $result.Applicable | Should-BeFalse
            $result.Applicability | Should-Be $Code
            $result.Details | Should-BeLikeString "$Text*less than the configured minimum."
            $result.Reason | Should-BeLikeString "${Name}: * against $Value; Intune reports Not applicable"
        }

        It 'compares the release as a build and says the text was not observed' {
            $result = Test-IntuneWin32Requirement -MinimumWindowsRelease Windows11_25H2
            $result.Applicable | Should-BeFalse
            $result.Applicability | Should-BeNull
            $result.Details | Should-BeLikeString '*not observed*'
            $result.Checks[0].Expected | Should-Be 'Windows11_25H2 (build 26200)'
            (Test-IntuneWin32Requirement -MinimumWindowsRelease '21H2').Applicable | Should-BeTrue
        }

        It 'reports the first failed check when several fail, and keeps every check' {
            $intuneWin32RequirementSplat = @{
                Architecture       = 'x86'
                MinimumMemoryMB    = 1000000
                MinimumCpuSpeedMHz = 9000
            }
            $result = Test-IntuneWin32Requirement @intuneWin32RequirementSplat
            $result.Applicability | Should-Be 1000
            @($result.Checks | Where-Object { -not $_.Met }).Count | Should-Be 3
            $result.Checks[2].Applicability | Should-BeNull
        }
    }
}
