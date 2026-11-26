#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The device facts the base requirements read: shape and plausibility on the machine running the
    tests, since the values themselves are machine-specific.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }
    $script:Fact = InModuleScope IntuneScriptLab { Get-IslDeviceFact }
}

Describe 'Get-IslDeviceFact' -Tag 'Integration', 'Private' {

    It 'names the architecture the way the requirements do' {
        @('x86', 'x64', 'arm64') | Should-ContainCollection $script:Fact.Architecture
        $script:Fact.PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.DeviceFact'
    }

    It 'reads a Windows 10 or later build number' {
        $script:Fact.Build | Should-BeGreaterThanOrEqual 10240
    }

    It 'reports positive disk space, memory, processor count and CPU speed' {
        $script:Fact.FreeDiskSpaceMB | Should-BeGreaterThan 0
        $script:Fact.MemoryMB | Should-BeGreaterThan 0
        $script:Fact.Processors | Should-BeGreaterThanOrEqual 1
        $script:Fact.CpuSpeedMHz | Should-BeGreaterThanOrEqual 0
    }
}
