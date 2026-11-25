#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The AST helper every rule is built on. Type names are matched as strings so the module
    loads on Windows PowerShell 5.1, where the PowerShell 7 node types do not exist.
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
try { Get-Item 'C:\a' -ErrorAction Stop } catch { exit 1 }
1..2 | ForEach-Object { exit 2 }
exit 0
'@
    $parser = [System.Management.Automation.Language.Parser]
    $script:Ast = $parser::ParseInput($script:Source, [ref]$null, [ref]$null)
}

Describe 'Find-IslAstNode' -Tag 'Unit', 'Private' {

    It 'finds nodes by type name and applies the predicate' {
        InModuleScope IntuneScriptLab -Parameters @{ Ast = $script:Ast } {
            @(Find-IslAstNode -Ast $Ast -TypeName ExitStatementAst).Count | Should-Be 3
            $where = { param($node) $node.Pipeline.Extent.Text -eq '2' }
            @(Find-IslAstNode -Ast $Ast -TypeName ExitStatementAst -Where $where).Count | Should-Be 1
        }
    }

    It 'returns nodes of several types in document order' {
        InModuleScope IntuneScriptLab -Parameters @{ Ast = $script:Ast } {
            $nodes = @(Find-IslAstNode -Ast $Ast -TypeName ExitStatementAst, FunctionDefinitionAst)
            $nodes.Count | Should-Be 4
            $nodes[0].GetType().Name | Should-Be 'FunctionDefinitionAst'
            $offsets = @($nodes | ForEach-Object { $_.Extent.StartOffset })
            for ($i = 1; $i -lt $offsets.Count; $i++) { $offsets[$i] | Should-BeGreaterThan $offsets[$i - 1] }
        }
    }

    It 'returns nothing for a type that is not in the tree' {
        InModuleScope IntuneScriptLab -Parameters @{ Ast = $script:Ast } {
            @(Find-IslAstNode -Ast $Ast -TypeName TernaryExpressionAst).Count | Should-Be 0
        }
    }
}
