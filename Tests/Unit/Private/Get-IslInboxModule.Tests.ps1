#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The in-box module table IslModuleDependency reports from, held against a Windows client's own
    Windows PowerShell: every listed module is there under the system module paths, except the
    engine module and the ones a Home edition does not ship, and nothing is there that the table
    does not name or this file does not account for. The host is asked as a child process, so the
    test gives the same answer whichever host runs it; a server has a different set and is skipped.
#>

BeforeDiscovery {
    $script:ClientHost = $false
    if (Get-Command powershell.exe -ErrorAction SilentlyContinue) {
        # ProductType 1 is a workstation; the table describes a client, and a server's set differs
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
        $script:ClientHost = [int]$os.ProductType -eq 1
    }
}

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    $script:Table = @(InModuleScope IntuneScriptLab { Get-IslInboxModule })

    # Listed, and rightly, but not a folder Get-Module -ListAvailable finds: the engine's own module
    $script:EngineModule = 'Microsoft.PowerShell.Core'
    # Pro and Enterprise features a Home edition does not ship (Windows 11 Home 24H2, ARM64)
    $script:EditionOnly = 'AppLocker', 'AppvClient', 'AssignedAccess', 'BranchCache', 'ConfigCI', 'iSCSI', 'UEV'
    # Windows features that put a module under System32 when they are turned on: Hyper-V and the
    # container and host-guardian family. HostNetworkingService is there on a Windows 11 Home ARM64
    # host without the feature. None is on a plain device, so none is in the table
    $script:FeatureModules = 'Hyper-V', 'HgsClient', 'HgsDiagnostics', 'HostComputeService',
    'HostNetworkingService'

    # Discovery-time variables do not reach the run, so the lookup is repeated here
    $script:ClientHost = $false
    if (Get-Command powershell.exe -ErrorAction SilentlyContinue) {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
        $script:ClientHost = [int]$os.ProductType -eq 1
    }
    if ($script:ClientHost) {
        # What the host's Windows PowerShell has under the two system module paths, the ones a
        # SYSTEM session under the agent reads (REM-PSMODULEPATH), kept apart: System32 is Windows'
        # own, Program Files is where installed software and the Gallery's AllUsers scope land
        $probe = {
            $windows = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\Modules"
            $programs = "$env:ProgramFiles\WindowsPowerShell\Modules"
            $available = Get-Module -ListAvailable
            $under = {
                param($Root)
                @($available | Where-Object { $_.ModuleBase.StartsWith($Root, 'OrdinalIgnoreCase') } |
                        Select-Object -ExpandProperty Name -Unique | Sort-Object -Unique)
            }
            # The engine module has no folder and Import-Module of it fails; its commands are there
            $engine = (Get-Command -Name Get-Command).ModuleName
            @{ Windows = & $under $windows; Programs = & $under $programs; Engine = $engine } |
                ConvertTo-Json -Compress
        }
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($probe.ToString()))
        $raw = & powershell.exe -NoProfile -NonInteractive -EncodedCommand $encoded 2>&1
        $answer = ($raw | Where-Object { "$_".StartsWith('{') } | Select-Object -Last 1) | ConvertFrom-Json
        $script:WindowsModules = @($answer.Windows)
        $script:HostModules = @($answer.Windows) + @($answer.Programs)
        $script:HostEngineModule = "$($answer.Engine)"
    }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Get-IslInboxModule' -Tag 'Unit', 'Private' {

    It 'names each module once' {
        $script:Table.Count | Should-BeGreaterThan 80
        @($script:Table | Sort-Object -Unique).Count | Should-Be $script:Table.Count
        $script:Table | Should-ContainCollection 'Microsoft.PowerShell.Utility'
        $script:Table | Should-ContainCollection 'ScheduledTasks'
        $script:Table | Should-NotContainCollection 'ActiveDirectory'
    }

    Context 'Against this Windows client' -Skip:(-not $script:ClientHost) {
        It 'has every listed module under the system module paths, or is a Home edition without the feature' {
            $script:HostModules.Count | Should-BeGreaterThan 50
            $missing = @($script:Table | Where-Object {
                    $_ -ne $script:EngineModule -and $_ -notin $script:EditionOnly -and
                    $_ -notin $script:HostModules
                })
            $missing | Should-BeCollection @()
        }

        It 'has the engine module''s commands without a module folder for it' {
            $script:HostModules | Should-NotContainCollection $script:EngineModule
            $script:HostEngineModule | Should-Be $script:EngineModule
        }

        It 'has nothing under the Windows module folder that the table or this file does not account for' {
            # System32 only: a GitHub runner has fifty installed modules under Program Files, and so
            # may any managed device. A module here that is in neither list is either new to
            # Windows, in which case the table is behind, or a feature of this host, in which case
            # it goes in FeatureModules
            $unlisted = @($script:WindowsModules | Where-Object {
                    $_ -notin $script:Table -and $_ -notin $script:FeatureModules
                })
            $unlisted | Should-BeCollection @()
        }
    }
}
