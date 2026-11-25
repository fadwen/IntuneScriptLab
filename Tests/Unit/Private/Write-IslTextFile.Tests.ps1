#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    One text section of the diagnostic package, written below its staging folder.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    function script:Write-Section {
        <#
        .SYNOPSIS
            Writes lines to a file below a folder through Write-IslTextFile.

        .DESCRIPTION
            Calls the private function inside the module with the folder, the relative path and the
            lines, which are passed on as given, $null included.

        .PARAMETER Root
            The folder the file is written below.

        .PARAMETER RelativePath
            The path of the file relative to Root.

        .PARAMETER Line
            The lines to write. $null is passed on as it is.

        .EXAMPLE
            Write-Section -Root $script:Root -RelativePath 'Manifest.txt' -Line 'new'

            Writes one line to Manifest.txt below the test folder.

        .INPUTS
            None.

        .OUTPUTS
            None.
        #>
        [CmdletBinding()]
        [OutputType([void])]
        param(
            [string]$Root,

            [string]$RelativePath,

            [AllowNull()]
            [string[]]$Line
        )

        $parameters = @{ Root = $Root; RelativePath = $RelativePath; Line = $Line }
        InModuleScope IntuneScriptLab -Parameters @{ Parameters = $parameters } {
            Write-IslTextFile @Parameters
        }
    }
}

Describe 'Write-IslTextFile' -Tag 'Unit', 'Private' {

    BeforeEach {
        $script:Root = Join-Path $TestDrive "staging-$([guid]::NewGuid().ToString('N'))"
        $null = New-Item -ItemType Directory -Path $script:Root
    }

    It 'creates the folders on the way and writes UTF-8 without a byte order mark' {
        $greeting = 'Gr' + [char]0xFC + [char]0xDF + 'e'
        Write-Section -Root $script:Root -RelativePath 'Registry\Scripts.txt' -Line 'first', $greeting

        $file = Join-Path $script:Root 'Registry\Scripts.txt'
        $bytes = [System.IO.File]::ReadAllBytes($file)
        $bytes[0] | Should-Be ([byte][char]'f')
        $lines = [System.IO.File]::ReadAllLines($file, [System.Text.UTF8Encoding]::new($false))
        $lines | Should-BeCollection -Count 2
        $lines[0] | Should-Be 'first'
        $lines[1] | Should-Be $greeting
    }

    It 'writes an empty file for no lines' {
        Write-Section -Root $script:Root -RelativePath 'Device\dsregcmd.txt' -Line $null

        (Get-Item -LiteralPath (Join-Path $script:Root 'Device\dsregcmd.txt')).Length | Should-Be 0
    }

    It 'replaces a file that is there' {
        Write-Section -Root $script:Root -RelativePath 'Manifest.txt' -Line 'old', 'older'
        Write-Section -Root $script:Root -RelativePath 'Manifest.txt' -Line 'new'

        [System.IO.File]::ReadAllLines((Join-Path $script:Root 'Manifest.txt')) | Should-BeCollection @('new')
    }

    It 'writes the file when -WhatIf reached it through the preference, as the command has asked' {
        InModuleScope IntuneScriptLab -Parameters @{ Root = $script:Root } {
            $WhatIfPreference = $true
            Write-IslTextFile -Root $Root -RelativePath 'Preview\x.txt' -Line 'x'
        }

        [System.IO.File]::ReadAllLines((Join-Path $script:Root 'Preview\x.txt')) | Should-BeCollection @('x')
    }

    It 'ends with an error when the file cannot be written' {
        # A folder in the place of the file
        $null = New-Item -ItemType Directory -Path (Join-Path $script:Root 'Manifest.txt')

        { Write-Section -Root $script:Root -RelativePath 'Manifest.txt' -Line 'x' } |
            Should-Throw -ExceptionMessage '*Manifest.txt*'
    }
}
