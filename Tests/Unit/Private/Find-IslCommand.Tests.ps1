#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Command invocations in a syntax tree, found by name.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }
    $script:Source = @'
try { Get-Item 'C:\a' -ErrorAction Stop } catch { exit 1 }
try { Get-Item 'C:\b' } finally { }
Write-Output 'plain'
'@
    $parser = [System.Management.Automation.Language.Parser]
    $script:Ast = $parser::ParseInput($script:Source, [ref]$null, [ref]$null)
}

Describe 'Find-IslCommand' -Tag 'Unit', 'Private' {

    It 'matches command names case-insensitively, any of several' {
        InModuleScope IntuneScriptLab -Parameters @{ Ast = $script:Ast } {
            @(Find-IslCommand -Ast $Ast -Name 'get-item').Count | Should-Be 2
            $several = @(Find-IslCommand -Ast $Ast -Name 'Write-Output', 'Get-Item')
            $several.Count | Should-Be 3
            # Document order whatever the order of the names asked for
            $names = @($several | ForEach-Object { $_.GetCommandName() })
            $names.Count | Should-Be 3
            $names[0] | Should-Be 'Get-Item'
            $names[1] | Should-Be 'Get-Item'
            $names[2] | Should-Be 'Write-Output'
            @(Find-IslCommand -Ast $Ast -Name 'Remove-Item').Count | Should-Be 0
        }
    }
}
