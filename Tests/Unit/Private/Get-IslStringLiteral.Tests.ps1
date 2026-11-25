#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The string literals of a syntax tree.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }
    $script:Source = @'
Get-Item 'C:\a'
$name = "expandable $env:X"
Write-Output 'plain'
'@
    $parser = [System.Management.Automation.Language.Parser]
    $script:Ast = $parser::ParseInput($script:Source, [ref]$null, [ref]$null)
}

Describe 'Get-IslStringLiteral' -Tag 'Unit', 'Private' {

    It 'returns constant and expandable strings' {
        InModuleScope IntuneScriptLab -Parameters @{ Ast = $script:Ast } {
            $texts = @(Get-IslStringLiteral -Ast $Ast).Extent.Text
            $texts | Should-ContainCollection "'plain'"
            $texts | Should-ContainCollection '"expandable $env:X"'
            $texts | Should-ContainCollection "'C:\a'"
        }
    }
}
