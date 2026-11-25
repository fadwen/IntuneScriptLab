#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The node and command index of a syntax tree, built once for each tree.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }
    $script:Source = @'
Get-Item 'C:\a'
& $tool
write-output 'x'
Get-Item 'C:\b'
'@
    $parser = [System.Management.Automation.Language.Parser]
    $script:Ast = $parser::ParseInput($script:Source, [ref]$null, [ref]$null)
}

Describe 'Get-IslAstIndex' -Tag 'Unit', 'Private' {

    It 'indexes the same tree once' {
        InModuleScope IntuneScriptLab -Parameters @{ Ast = $script:Ast } {
            $first = Get-IslAstIndex -Ast $Ast
            $second = Get-IslAstIndex -Ast $Ast

            $first | Should-HaveType 'IntuneScriptLab.AstIndex'
            [object]::ReferenceEquals($first, $second) | Should-BeTrue
        }
    }

    It 'lists the nodes of a type that FindAll finds, in the order it finds them' {
        InModuleScope IntuneScriptLab -Parameters @{ Ast = $script:Ast } {
            $walked = @($Ast.FindAll({ param($node) $node.GetType().Name -eq 'CommandAst' }, $true))
            $indexed = @((Get-IslAstIndex -Ast $Ast).ByType['CommandAst'])

            $indexed.Count | Should-Be $walked.Count
            for ($i = 0; $i -lt $walked.Count; $i++) {
                [object]::ReferenceEquals($walked[$i], $indexed[$i]) | Should-BeTrue
            }
        }
    }

    It 'groups commands by name without regard to case, and leaves out a command without one' {
        InModuleScope IntuneScriptLab -Parameters @{ Ast = $script:Ast } {
            $byCommand = (Get-IslAstIndex -Ast $Ast).ByCommand

            $byCommand['get-item'].Count | Should-Be 2
            $byCommand['Write-Output'].Count | Should-Be 1
            $byCommand.Count | Should-Be 2
        }
    }

    It 'gives a sub-tree an index of its own' {
        InModuleScope IntuneScriptLab -Parameters @{ Ast = $script:Ast } {
            $statement = $Ast.EndBlock.Statements[0]

            [object]::ReferenceEquals((Get-IslAstIndex -Ast $statement), (Get-IslAstIndex -Ast $Ast)) |
                Should-BeFalse
        }
    }
}
