#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The run settings a local script states for itself: a directive in the file, then its
    settings file.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }

    function script:Write-Script {
        param([string]$Folder, [string]$Text)
        $null = New-Item -ItemType Directory -Path $Folder -Force
        $file = Join-Path $Folder 'detect.ps1'
        [System.IO.File]::WriteAllText($file, $Text)
        $file
    }

    function script:Get-Setting {
        param([string]$File, [hashtable]$Extra = @{})
        InModuleScope IntuneScriptLab -Parameters @{ File = $File; Extra = $Extra } {
            Get-IslLocalScriptSetting -File $File -Cache @{} @Extra
        }
    }
}

Describe 'Get-IslLocalScriptSetting' -Tag 'Unit', 'Private' {

    It 'reads the settings of a directive in the file' {
        $file = Write-Script -Folder (Join-Path $TestDrive 'directive') -Text (
            "# IntuneScriptLab: Context=User; Architecture=x86`nexit 0")
        $settings = Get-Setting -File $file

        $settings | Should-HaveType ([hashtable])
        $settings['Context'] | Should-Be 'User'
        $settings['Architecture'] | Should-Be 'x86'
        $settings.ContainsKey('EnforceSignatureCheck') | Should-BeFalse
    }

    It 'takes a setting the caller gives, and lets the directive win over it' {
        $file = Write-Script -Folder (Join-Path $TestDrive 'both') -Text "# IntuneScriptLab: Context=User`nexit 0"
        $settings = Get-Setting -File $file -Extra @{ Settings = @{ Context = 'System'; Architecture = 'x86' } }

        $settings['Context'] | Should-Be 'User'
        $settings['Architecture'] | Should-Be 'x86'
    }

    It 'gives no setting for a script that states none' {
        $file = Write-Script -Folder (Join-Path $TestDrive 'none') -Text 'exit 0'

        (Get-Setting -File $file).Count | Should-Be 0
    }

    It 'ends with the error of a settings value that is not allowed' {
        $file = Write-Script -Folder (Join-Path $TestDrive 'bad') -Text 'exit 0'

        { Get-Setting -File $file -Extra @{ Settings = @{ Context = 'Kiosk' } } } |
            Should-Throw -FullyQualifiedErrorId 'SettingsInvalid*'
    }
}
