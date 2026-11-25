#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Which line endings a script's text uses.
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

Describe 'Get-IslLineEnding' -Tag 'Unit', 'Private' {

    It 'gives <Expected> for <Case>' -ForEach @(
        @{ Case = 'CRLF lines'; Text = "a`r`nb`r`n"; Expected = 'CRLF' }
        @{ Case = 'LF lines'; Text = "a`nb`n"; Expected = 'LF' }
        @{ Case = 'a mix'; Text = "a`nb`r`n"; Expected = 'CRLF' }
        @{ Case = 'one line'; Text = 'a'; Expected = '' }
    ) {
        InModuleScope IntuneScriptLab -Parameters @{ Text = $Text } { Get-IslLineEnding -Text $Text } |
            Should-Be $Expected
    }
}
