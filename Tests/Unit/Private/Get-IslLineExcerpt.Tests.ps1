#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    A line of a script, shortened for a drift message.
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

Describe 'Get-IslLineExcerpt' -Tag 'Unit', 'Private' {

    It 'trims a short line' {
        InModuleScope IntuneScriptLab { Get-IslLineExcerpt -Line '    exit 1  ' } | Should-Be 'exit 1'
    }

    It 'cuts a line longer than 60 characters to 57 and three dots' {
        $excerpt = InModuleScope IntuneScriptLab { Get-IslLineExcerpt -Line ('x' * 80) }

        $excerpt | Should-Be (('x' * 57) + '...')
    }

    It 'keeps a line of exactly 60 characters' {
        InModuleScope IntuneScriptLab { Get-IslLineExcerpt -Line ('y' * 60) } | Should-Be ('y' * 60)
    }
}
