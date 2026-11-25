#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Whether a node of a syntax tree is in the body of a try that has a catch.
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
try { Get-Item 'C:\a' -ErrorAction Stop } catch { exit 1 }
try { Get-Item 'C:\b' } finally { }
'@
    $parser = [System.Management.Automation.Language.Parser]
    $script:Ast = $parser::ParseInput($script:Source, [ref]$null, [ref]$null)
}

Describe 'Test-IslInsideTryWithCatch' -Tag 'Unit', 'Private' {

    It 'is true only for the body of a try that has a catch' {
        InModuleScope IntuneScriptLab -Parameters @{ Ast = $script:Ast } {
            $guarded, $bare = Find-IslCommand -Ast $Ast -Name 'Get-Item'
            Test-IslInsideTryWithCatch -Node $guarded | Should-BeTrue
            Test-IslInsideTryWithCatch -Node $bare | Should-BeFalse
            # The catch block itself is not the try body
            $inCatch = @(Find-IslAstNode -Ast $Ast -TypeName ExitStatementAst)[0]
            Test-IslInsideTryWithCatch -Node $inCatch | Should-BeFalse
        }
    }
}
