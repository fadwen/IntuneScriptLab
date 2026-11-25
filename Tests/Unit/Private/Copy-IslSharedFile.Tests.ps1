#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The copy of a log that the agent holds open for writing.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }

    function script:Copy-Shared {
        param([string]$Source, [string]$Destination)
        InModuleScope IntuneScriptLab -Parameters @{ Source = $Source; Destination = $Destination } {
            Copy-IslSharedFile -Source $Source -Destination $Destination
        }
    }
}

Describe 'Copy-IslSharedFile' -Tag 'Unit', 'Private' {

    It 'copies a file that another stream holds open for writing, as it stands' {
        $source = Join-Path $TestDrive 'IntuneManagementExtension.log'
        $destination = Join-Path $TestDrive 'copy-open.log'
        # Open for writing and shared for reading only, as the agent holds its log
        $writer = [System.IO.File]::Open($source, 'Create', 'Write', 'Read')
        try {
            $bytes = [System.Text.Encoding]::ASCII.GetBytes("line one`r`n")
            $writer.Write($bytes, 0, $bytes.Length)
            $writer.Flush()
            # What the share mode is for: a reader that allows only other readers is refused
            { [System.IO.File]::OpenRead($source).Dispose() } | Should-Throw

            Copy-Shared -Source $source -Destination $destination
        } finally {
            $writer.Dispose()
        }

        [System.IO.File]::ReadAllText($destination) | Should-Be "line one`r`n"
    }

    It 'copies a file that a writer holds with delete access, as one that rotates its log does' {
        $source = Join-Path $TestDrive 'Rotating.log'
        $destination = Join-Path $TestDrive 'copy-rotating.log'
        $rights = [System.Security.AccessControl.FileSystemRights]'Write, Delete'
        $share = [System.IO.FileShare]'ReadWrite, Delete'
        if ($PSVersionTable.PSVersion -lt [version]'6.0') {
            $writer = [System.IO.FileStream]::new($source, 'Create', $rights, $share, 4096, 'None')
        } else {
            $writer = [System.IO.FileSystemAclExtensions]::Create(
                [System.IO.FileInfo]$source, 'Create', $rights, $share, 4096, 'None', $null)
        }
        try {
            $bytes = [System.Text.Encoding]::ASCII.GetBytes("rotating`r`n")
            $writer.Write($bytes, 0, $bytes.Length)
            $writer.Flush()
            # What delete sharing is for: a reader that shares only reading and writing is refused
            { [System.IO.File]::Open($source, 'Open', 'Read', 'ReadWrite').Dispose() } | Should-Throw

            Copy-Shared -Source $source -Destination $destination
        } finally {
            $writer.Dispose()
        }

        [System.IO.File]::ReadAllText($destination) | Should-Be "rotating`r`n"
    }

    It 'removes the part copy when the source cannot be read to its end' {
        $source = Join-Path $TestDrive 'Locked.log'
        $destination = Join-Path $TestDrive 'copy-locked.log'
        [System.IO.File]::WriteAllText($source, ('x' * 1000))
        # A byte range that another stream has locked cannot be read, though the file opens
        $holder = [System.IO.File]::Open($source, 'Open', 'ReadWrite', 'ReadWrite, Delete')
        try {
            $holder.Lock(0, 1000)
            { Copy-Shared -Source $source -Destination $destination } | Should-Throw -ExceptionMessage '*lock*'
        } finally {
            $holder.Dispose()
        }

        Test-Path -LiteralPath $destination | Should-BeFalse
    }

    It 'replaces a file that is at the destination' {
        $source = Join-Path $TestDrive 'Agent.log'
        $destination = Join-Path $TestDrive 'copy-replaced.log'
        [System.IO.File]::WriteAllText($source, 'new')
        [System.IO.File]::WriteAllText($destination, 'old and longer')

        Copy-Shared -Source $source -Destination $destination

        [System.IO.File]::ReadAllText($destination) | Should-Be 'new'
    }

    It 'ends with an error for a source that is not there' {
        $missing = Join-Path $TestDrive 'not-there.log'

        $never = Join-Path $TestDrive 'never.log'
        { Copy-Shared -Source $missing -Destination $never } | Should-Throw -ExceptionMessage '*not-there.log*'
        Test-Path -LiteralPath $never | Should-BeFalse
    }

    It 'copies when -WhatIf reached it through the preference, as the command has asked' {
        $source = Join-Path $TestDrive 'Preview.log'
        $destination = Join-Path $TestDrive 'copy-preview.log'
        [System.IO.File]::WriteAllText($source, 'previewed')
        InModuleScope IntuneScriptLab -Parameters @{ Source = $source; Destination = $destination } {
            $WhatIfPreference = $true
            Copy-IslSharedFile -Source $Source -Destination $Destination
        }

        [System.IO.File]::ReadAllText($destination) | Should-Be 'previewed'
    }
}
