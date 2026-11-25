#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The SHA-256 hash of a script's bytes.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }
}

Describe 'Get-IslContentHash' -Tag 'Unit', 'Private' {

    It 'gives the lower-case hex SHA-256 of <Case>' -ForEach @(
        @{
            Case = 'abc'; Text = 'abc'
            Expected = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
        }
        @{
            Case = 'no bytes'; Text = ''
            Expected = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
        }
    ) {
        $hash = InModuleScope IntuneScriptLab -Parameters @{ Text = $Text } {
            Get-IslContentHash -Bytes ([System.Text.Encoding]::ASCII.GetBytes($Text))
        }

        $hash | Should-Be $Expected
    }
}
