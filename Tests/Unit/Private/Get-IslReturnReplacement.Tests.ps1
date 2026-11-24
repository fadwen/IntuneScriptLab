#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The edit that says what a script-scope return already does, for the exit-code rule.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }

    # The syntax tree of a script given as text
    function script:ConvertTo-Ast {
        param([string]$Text)
        [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null)
    }

    function script:Get-Replacement {
        param([string]$Text)
        $return = (ConvertTo-Ast $Text).Find({
                param($node) $node -is [System.Management.Automation.Language.ReturnStatementAst]
            }, $true)
        InModuleScope IntuneScriptLab -Parameters @{ Return = $return } {
            Get-IslReturnReplacement -Return $Return
        }
    }
}

Describe 'Get-IslReturnReplacement' -Tag 'Unit', 'Private' {

    It 'gives <Expected> for <Text>' -ForEach @(
        @{ Text = 'return'; Expected = 'exit 0' }
        @{ Text = 'return 1'; Expected = '1; exit 0' }
        @{ Text = "return 'installed'"; Expected = "'installed'; exit 0" }
    ) {
        Get-Replacement -Text $Text | Should-Be $Expected
    }
}
