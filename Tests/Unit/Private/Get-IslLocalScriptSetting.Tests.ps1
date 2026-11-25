#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The run settings a local script states for itself: a directive in the file, then its
    settings file.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    function script:Write-Script {
        <#
        .SYNOPSIS
            Writes detect.ps1 into a folder and returns its path.

        .DESCRIPTION
            Creates the folder if it is not there and writes the text to detect.ps1 in it, as UTF-8
            without a byte order mark, so that a case can give the file the directive it tests.

        .PARAMETER Folder
            The folder of the script.

        .PARAMETER Text
            The text of the script.

        .EXAMPLE
            Write-Script -Folder (Join-Path $TestDrive 'none') -Text 'exit 0'

            Writes a script without a directive and returns its path.

        .INPUTS
            None.

        .OUTPUTS
            System.String. The path of detect.ps1.
        #>
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [string]$Folder,

            [string]$Text
        )

        $null = New-Item -ItemType Directory -Path $Folder -Force
        $file = Join-Path $Folder 'detect.ps1'
        [System.IO.File]::WriteAllText($file, $Text)
        $file
    }

    function script:Get-Setting {
        <#
        .SYNOPSIS
            Gets the run settings of a script from Get-IslLocalScriptSetting.

        .DESCRIPTION
            Runs the module's private Get-IslLocalScriptSetting inside the module on the file, with
            an empty cache and the parameters the case adds.

        .PARAMETER File
            The path of the script.

        .PARAMETER Extra
            Parameters of Get-IslLocalScriptSetting that the case adds, such as
            @{ Settings = @{ Context = 'System' } }.

        .EXAMPLE
            Get-Setting -File $file

            Returns the settings that the script's directive states.

        .INPUTS
            None.

        .OUTPUTS
            System.Collections.Hashtable. The settings by name.
        #>
        [CmdletBinding()]
        [OutputType([hashtable])]
        param(
            [string]$File,

            [hashtable]$Extra = @{}
        )

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
