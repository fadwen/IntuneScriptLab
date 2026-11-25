#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Which line endings a script's text uses.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
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
