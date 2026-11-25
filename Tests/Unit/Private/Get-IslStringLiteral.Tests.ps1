#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The string literals of a syntax tree.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
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
