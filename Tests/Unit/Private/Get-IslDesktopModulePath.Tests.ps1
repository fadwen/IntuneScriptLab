#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The module path a child process is given. Under PowerShell 7 the session's path lists
    PowerShell 7's own folders, which a powershell.exe child must not see; under Windows PowerShell
    there is nothing to remove.
#>

BeforeDiscovery {
    $script:OnCore = $PSVersionTable.PSEdition -eq 'Core'
}

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force

    $script:CoreFolders = @(
        Join-Path $PSHOME 'Modules'
        Join-Path $env:ProgramFiles 'PowerShell\Modules'
        Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Modules'
    )
    $script:DesktopFolders = @(
        Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules'
        Join-Path $env:WINDIR 'system32\WindowsPowerShell\v1.0\Modules'
    )

    function Get-ModulePath {
        param([string]$ModulePath)
        InModuleScope IntuneScriptLab -Parameters @{ ModulePath = $ModulePath } {
            Get-IslDesktopModulePath -ModulePath $ModulePath
        }
    }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Get-IslDesktopModulePath' -Tag 'Unit', 'Private' {

    Context 'Under PowerShell 7' -Skip:(-not $script:OnCore) {
        It 'removes the three folders PowerShell 7 adds for itself and keeps the rest in order' {
            $session = 'C:\Session\Modules'
            $given = @($script:CoreFolders[2], $script:CoreFolders[1], $script:CoreFolders[0]) +
                $script:DesktopFolders[0] + $session + $script:DesktopFolders[1]
            Get-ModulePath ($given -join ';') |
                Should-Be (@($script:DesktopFolders[0], $session, $script:DesktopFolders[1]) -join ';')
        }

        It 'matches a folder whatever its case or trailing backslash' {
            $given = "$($script:CoreFolders[0].ToLowerInvariant())\;$($script:DesktopFolders[1])"
            Get-ModulePath $given | Should-Be $script:DesktopFolders[1]
        }

        It 'returns an empty string when nothing is left' {
            Get-ModulePath ($script:CoreFolders -join ';') | Should-Be ''
        }

        It 'reads the session path when none is given' {
            $result = InModuleScope IntuneScriptLab { Get-IslDesktopModulePath }
            $entries = @($result -split ';')
            @($entries | Where-Object { $_ -in $script:CoreFolders }).Count | Should-Be 0
            $entries.Count | Should-BeGreaterThan 0
        }
    }

    Context 'Under Windows PowerShell' -Skip:$script:OnCore {
        It 'returns the path as it is, $PSHOME\Modules included' {
            $given = "$(Join-Path $PSHOME 'Modules');C:\Session\Modules"
            Get-ModulePath $given | Should-Be $given
        }
    }
}
