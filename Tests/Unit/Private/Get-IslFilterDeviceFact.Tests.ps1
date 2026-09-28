#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The local values the filter evaluator compares: shape and plausibility on the machine running
    the tests, and the join-type mapping from a fixed dsregcmd status (the two lab devices
    reported "Azure AD joined" / Corporate and "Azure AD registered" / Personal, FLT-E08, FLT-E09,
    FLT-E23, FLT-E24).
#>

BeforeDiscovery {
    $script:OnWindows = $PSVersionTable.PSVersion.Major -lt 6 -or $IsWindows
}

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    $script:OnWindows = $PSVersionTable.PSVersion.Major -lt 6 -or $IsWindows

    function script:Get-FactWithStatus {
        param([string[]]$Status)
        InModuleScope IntuneScriptLab -Parameters @{ Status = $Status } {
            Mock Get-IslDsregStatus { $Status }
            Get-IslFilterDeviceFact
        }
    }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Get-IslFilterDeviceFact' -Tag 'Unit', 'Private' -Skip:(-not $script:OnWindows) {

    It 'reports every filter property, with the tenant-side ones empty' {
        $fact = InModuleScope IntuneScriptLab { Get-IslFilterDeviceFact }
        $expected = @('deviceName', 'manufacturer', 'model', 'osVersion', 'operatingSystemVersion',
            'operatingSystemSKU', 'cpuArchitecture', 'deviceTrustType', 'deviceOwnership',
            'enrollmentProfileName', 'deviceCategory', 'isTpmAttested')
        @($fact.Keys | Sort-Object) | Should-BeCollection @($expected | Sort-Object)
        $fact.deviceName | Should-Be $env:COMPUTERNAME
        $fact.enrollmentProfileName | Should-BeNull
        $fact.deviceCategory | Should-BeNull
        $fact.isTpmAttested | Should-BeNull
    }

    It 'names the architecture the way the filter does (amd64, not x64)' {
        $fact = InModuleScope IntuneScriptLab { Get-IslFilterDeviceFact }
        @('amd64', 'x86', 'arm64') | Should-ContainCollection $fact.cpuArchitecture
    }

    It 'reads a four-part version with the update build revision, the same for both version properties' {
        $fact = InModuleScope IntuneScriptLab { Get-IslFilterDeviceFact }
        $fact.osVersion | Should-MatchString '^10\.0\.\d+\.\d+$'
        $fact.operatingSystemVersion | Should-Be $fact.osVersion
    }

    It 'names the SKU from the filter reference table, or keeps the number where the table has no name' {
        $fact = InModuleScope IntuneScriptLab { Get-IslFilterDeviceFact }
        $fact.operatingSystemSKU | Should-NotBeWhiteSpaceString
        $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem
        if ($operatingSystem.ProductType -eq 1) {
            # A workstation SKU is in the reference; a server (the CI runner) is not managed by Intune
            $fact.operatingSystemSKU | Should-NotMatchString '^\d+$'
        }
        else {
            $fact.operatingSystemSKU | Should-Be "$($operatingSystem.OperatingSystemSKU)"
        }
    }

    It 'maps the join type and infers the ownership: <Trust> / <Ownership>' -ForEach @(
        @{ Status = @('  AzureAdJoined : YES', '  DomainJoined : NO', '  WorkplaceJoined : NO')
            Trust = 'Azure AD joined'; Ownership = 'Corporate' }
        @{ Status = @('  AzureAdJoined : YES', '  DomainJoined : YES', '  WorkplaceJoined : NO')
            Trust = 'Hybrid Azure AD joined'; Ownership = 'Corporate' }
        @{ Status = @('  AzureAdJoined : NO', '  DomainJoined : NO', '  WorkplaceJoined : YES')
            Trust = 'Azure AD registered'; Ownership = 'Personal' }
        @{ Status = @('  AzureAdJoined : NO', '  DomainJoined : NO', '  WorkplaceJoined : NO')
            Trust = 'Unknown'; Ownership = 'Unknown' }
        @{ Status = @(); Trust = 'Unknown'; Ownership = 'Unknown' }
    ) {
        $fact = Get-FactWithStatus -Status $Status
        $fact.deviceTrustType | Should-Be $Trust
        $fact.deviceOwnership | Should-Be $Ownership
    }
}
