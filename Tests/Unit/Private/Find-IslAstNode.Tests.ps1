#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The AST helpers every rule is built on. Type names are matched as strings so the module
    loads on Windows PowerShell 5.1, where the PowerShell 7 node types do not exist.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
    $script:Source = @'
function Get-X { return 1 }
try { Get-Item 'C:\a' -ErrorAction Stop } catch { exit 1 }
try { Get-Item 'C:\b' } finally { }
1..2 | ForEach-Object { exit 2 }
$name = "expandable $env:X"
Write-Output 'plain'
exit 0
'@
    $parser = [System.Management.Automation.Language.Parser]
    $script:Ast = $parser::ParseInput($script:Source, [ref]$null, [ref]$null)
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Find-IslAstNode' -Tag 'Unit', 'Private' {

    It 'finds nodes by type name and applies the predicate' {
        InModuleScope IntuneScriptLab -Parameters @{ Ast = $script:Ast } {
            @(Find-IslAstNode -Ast $Ast -TypeName ExitStatementAst).Count | Should-Be 3
            $where = { param($node) $node.Pipeline.Extent.Text -eq '2' }
            @(Find-IslAstNode -Ast $Ast -TypeName ExitStatementAst -Where $where).Count | Should-Be 1
        }
    }

    It 'returns nothing for a type that is not in the tree' {
        InModuleScope IntuneScriptLab -Parameters @{ Ast = $script:Ast } {
            @(Find-IslAstNode -Ast $Ast -TypeName TernaryExpressionAst).Count | Should-Be 0
        }
    }
}

Describe 'Find-IslCommand' -Tag 'Unit', 'Private' {

    It 'matches command names case-insensitively, any of several' {
        InModuleScope IntuneScriptLab -Parameters @{ Ast = $script:Ast } {
            @(Find-IslCommand -Ast $Ast -Name 'get-item').Count | Should-Be 2
            @(Find-IslCommand -Ast $Ast -Name 'Get-Item', 'Write-Output').Count | Should-Be 3
            @(Find-IslCommand -Ast $Ast -Name 'Remove-Item').Count | Should-Be 0
        }
    }
}

Describe 'Test-IslCommandParameter' -Tag 'Unit', 'Private' {

    It 'matches a parameter by prefix, the way PowerShell binds it' {
        InModuleScope IntuneScriptLab -Parameters @{ Ast = $script:Ast } {
            $guarded, $bare = Find-IslCommand -Ast $Ast -Name 'Get-Item'
            Test-IslCommandParameter -Command $guarded -ParameterName ErrorAction | Should-BeTrue
            Test-IslCommandParameter -Command $bare -ParameterName ErrorAction | Should-BeFalse
        }
    }
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

Describe 'Test-IslInsideTryWithCatch' -Tag 'Unit', 'Private' {

    It 'is true only for the body of a try that has a catch' {
        InModuleScope IntuneScriptLab -Parameters @{ Ast = $script:Ast } {
            $guarded, $bare = Find-IslCommand -Ast $Ast -Name 'Get-Item'
            Test-IslInsideTryWithCatch -Node $guarded | Should-BeTrue
            Test-IslInsideTryWithCatch -Node $bare | Should-BeFalse
            # The catch block itself is not the try body
            $exits = @(Find-IslAstNode -Ast $Ast -TypeName ExitStatementAst)
            $inCatch = $exits | Where-Object { $_.Pipeline.Extent.Text -eq '1' }
            Test-IslInsideTryWithCatch -Node $inCatch | Should-BeFalse
        }
    }
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
