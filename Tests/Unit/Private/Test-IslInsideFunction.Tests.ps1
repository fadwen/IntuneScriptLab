#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Whether a node of a syntax tree is inside a function body or a script block.
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
function Get-X { return 1 }
1..2 | ForEach-Object { exit 2 }
exit 0
'@
    $parser = [System.Management.Automation.Language.Parser]
    $script:Ast = $parser::ParseInput($script:Source, [ref]$null, [ref]$null)
}

Describe 'Test-IslInsideFunction' -Tag 'Unit', 'Private' {

    It 'is true inside a function body and inside a nested script block, false at script level' {
        InModuleScope IntuneScriptLab -Parameters @{ Ast = $script:Ast } {
            $inFunction = Find-IslAstNode -Ast $Ast -TypeName ReturnStatementAst
            Test-IslInsideFunction -Node $inFunction[0] | Should-BeTrue
            $exits = @(Find-IslAstNode -Ast $Ast -TypeName ExitStatementAst)
            $inForEach = $exits | Where-Object { $_.Pipeline.Extent.Text -eq '2' }
            Test-IslInsideFunction -Node $inForEach | Should-BeTrue
            $atRoot = $exits | Where-Object { $_.Pipeline.Extent.Text -eq '0' }
            Test-IslInsideFunction -Node $atRoot | Should-BeFalse
        }
    }
}
