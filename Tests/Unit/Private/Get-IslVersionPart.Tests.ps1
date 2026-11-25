#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    A version text as the four numbers an assignment filter compares.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    function script:Get-Part {
        param([string]$Text)
        InModuleScope IntuneScriptLab -Parameters @{ Text = $Text } { @(Get-IslVersionPart -Text $Text) }
    }
}

Describe 'Get-IslVersionPart' -Tag 'Unit', 'Private' {

    It 'reads <Text> as <Expected>' -ForEach @(
        @{ Text = '10'; Expected = @(10, 0, 0, 0) }
        @{ Text = '10.0.26100'; Expected = @(10, 0, 26100, 0) }
        @{ Text = '10.0.26100.4202'; Expected = @(10, 0, 26100, 4202) }
        @{ Text = '9223372036854775807'; Expected = @([long]::MaxValue, 0, 0, 0) }
        @{ Text = ' 6.3 '; Expected = @(6, 3, 0, 0) }
    ) {
        $parts = Get-Part -Text $Text

        $parts | Should-BeCollection -Count 4
        for ($index = 0; $index -lt 4; $index++) {
            $parts[$index] | Should-Be ([long]$Expected[$index])
        }
    }

    It 'gives nothing for <Text>' -ForEach @(
        @{ Text = '' }
        @{ Text = 'Windows 11' }
        @{ Text = '1.2.3.4.5' }
        @{ Text = '10.0.' }
        @{ Text = '-1.0' }
        @{ Text = '10.0.99999999999999999999' }
    ) {
        Get-Part -Text $Text | Should-BeCollection @()
    }
}
