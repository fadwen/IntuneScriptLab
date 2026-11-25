#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The key that a tenant policy and its local folder or file are matched by.
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

Describe 'ConvertTo-IslNameKey' -Tag 'Unit', 'Private' {

    It 'gives <Expected> for <Value>' -ForEach @(
        @{ Value = 'Detect Printer (x64)'; Expected = 'detect_printer__x64_' }
        @{ Value = 'Widget: 2.0'; Expected = 'widget__2.0' }
        @{ Value = 'Fix-Widget_1'; Expected = 'fix-widget_1' }
        @{ Value = ''; Expected = '' }
    ) {
        InModuleScope IntuneScriptLab -Parameters @{ Value = $Value } { ConvertTo-IslNameKey -Value $Value } |
            Should-Be $Expected
    }
}
