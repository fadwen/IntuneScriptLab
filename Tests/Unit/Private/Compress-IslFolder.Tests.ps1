#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The zip of the diagnostic package, with forward slashes in its entry names on every host.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
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
            Compress-IslFolder -Folder $Folder -Destination $Zip @script:IslInternal
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

    It 'writes no archive under -WhatIf' {
        $zip = Join-Path $TestDrive 'preview.zip'
        InModuleScope IntuneScriptLab -Parameters @{ Folder = $script:Folder; Zip = $zip } {
            Compress-IslFolder -Folder $Folder -Destination $Zip -WhatIf
        }

        Test-Path -LiteralPath $zip | Should-BeFalse
    }
}
