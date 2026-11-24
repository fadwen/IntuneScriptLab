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
            Copy-IslSharedFile -Source $Source -Destination $Destination @script:IslInternal
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

        { Copy-Shared -Source $missing -Destination (Join-Path $TestDrive 'never.log') } | Should-Throw
    }
}
