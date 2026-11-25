#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Whether a command invocation passes a parameter, matched by prefix as PowerShell binds it.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }
    $script:Source = @'
Get-Item 'C:\a' -ErrorAction Stop
Get-Item 'C:\b'
Get-Item 'C:\c' -ErrorA Stop
'@
    $parser = [System.Management.Automation.Language.Parser]
    $script:Ast = $parser::ParseInput($script:Source, [ref]$null, [ref]$null)
}

Describe 'Test-IslCommandParameter' -Tag 'Unit', 'Private' {

    It 'matches a parameter by prefix, the way PowerShell binds it' {
        InModuleScope IntuneScriptLab -Parameters @{ Ast = $script:Ast } {
            $full, $bare, $prefix = Find-IslCommand -Ast $Ast -Name 'Get-Item'

            Test-IslCommandParameter -Command $full -ParameterName ErrorAction | Should-BeTrue
            Test-IslCommandParameter -Command $bare -ParameterName ErrorAction | Should-BeFalse
            Test-IslCommandParameter -Command $prefix -ParameterName ErrorAction | Should-BeTrue
        }
    }
}
