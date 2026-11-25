#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The zip of the diagnostic package, with forward slashes in its entry names on every host.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $script:Folder = Join-Path $TestDrive 'staging'
    foreach ($relative in 'Manifest.txt', 'Logs\Agent.log', 'Registry\Deep\Key.txt') {
        $path = Join-Path $script:Folder $relative
        $null = New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force
        [System.IO.File]::WriteAllText($path, $relative)
    }
    $null = New-Item -ItemType Directory -Path (Join-Path $script:Folder 'Empty')
}

Describe 'Compress-IslFolder' -Tag 'Unit', 'Private' {

    It 'writes one entry for each file, named with forward slashes, and returns the count' {
        $zip = Join-Path $TestDrive 'package.zip'
        $count = InModuleScope IntuneScriptLab -Parameters @{ Folder = $script:Folder; Zip = $zip } {
            Compress-IslFolder -Folder $Folder -Destination $Zip
        }

        $archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
        try {
            $names = @($archive.Entries | ForEach-Object { $_.FullName } | Sort-Object)
        } finally {
            $archive.Dispose()
        }
        $count | Should-Be 3
        $names | Should-BeCollection -Count 3
        $names[0] | Should-Be 'Logs/Agent.log'
        $names[1] | Should-Be 'Manifest.txt'
        $names[2] | Should-Be 'Registry/Deep/Key.txt'
    }

    It 'writes the archive when -WhatIf reached it through the preference, as the command has asked' {
        $zip = Join-Path $TestDrive 'preview.zip'
        $count = InModuleScope IntuneScriptLab -Parameters @{ Folder = $script:Folder; Zip = $zip } {
            $WhatIfPreference = $true
            Compress-IslFolder -Folder $Folder -Destination $Zip
        }

        $count | Should-Be 3
        Test-Path -LiteralPath $zip | Should-BeTrue
    }

    It 'ends with an error and leaves no archive when a file cannot be added' {
        $zip = Join-Path $TestDrive 'part.zip'
        $locked = Join-Path $script:Folder 'Registry\Deep\Key.txt'
        # A stream that writes to the file and shares only reading keeps the archive from opening it
        $holder = [System.IO.File]::Open($locked, 'Open', 'ReadWrite', 'Read')
        try {
            {
                InModuleScope IntuneScriptLab -Parameters @{ Folder = $script:Folder; Zip = $zip } {
                    Compress-IslFolder -Folder $Folder -Destination $Zip
                }
            } | Should-Throw -ExceptionMessage '*Key.txt*'
        } finally {
            $holder.Dispose()
        }

        Test-Path -LiteralPath $zip | Should-BeFalse
    }

    It 'ends with an error when the archive is there already, and leaves it as it was' {
        $zip = Join-Path $TestDrive 'taken.zip'
        [System.IO.File]::WriteAllText($zip, 'not a zip')

        {
            InModuleScope IntuneScriptLab -Parameters @{ Folder = $script:Folder; Zip = $zip } {
                Compress-IslFolder -Folder $Folder -Destination $Zip
            }
        } | Should-Throw -ExceptionMessage '*taken.zip*'
        [System.IO.File]::ReadAllText($zip) | Should-Be 'not a zip'
    }
}
