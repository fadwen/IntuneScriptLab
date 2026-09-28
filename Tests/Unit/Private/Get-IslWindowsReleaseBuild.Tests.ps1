#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The release-name-to-build table behind the minimum operating system requirement.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Get-IslWindowsReleaseBuild' -Tag 'Unit', 'Private' {

    It 'maps <Release> to build <Build>' -ForEach @(
        @{ Release = '1607';           Build = 14393 }
        @{ Release = '22H2';           Build = 19045 }
        @{ Release = 'Windows11_21H2'; Build = 22000 }
        @{ Release = 'Windows11_24H2'; Build = 26100 }
    ) {
        $build = InModuleScope IntuneScriptLab -Parameters @{ Release = $Release } {
            Get-IslWindowsReleaseBuild -Release $Release
        }
        $build | Should-Be $Build
    }

    It 'orders every release by build' {
        $builds = InModuleScope IntuneScriptLab {
            foreach ($release in '1607', '1809', '2004', '21H2', '22H2', 'Windows11_22H2', 'Windows11_24H2') {
                Get-IslWindowsReleaseBuild -Release $release
            }
        }
        $builds | Should-BeCollection ($builds | Sort-Object)
    }

    It 'refuses an unknown release' {
        { InModuleScope IntuneScriptLab { Get-IslWindowsReleaseBuild -Release 'Windows12' } } |
            Should-Throw -ExceptionMessage "*Unknown Windows release 'Windows12'*"
    }
}
