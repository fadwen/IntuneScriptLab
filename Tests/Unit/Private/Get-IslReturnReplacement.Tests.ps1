#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The edit that says what a script-scope return already does, for the exit-code rule.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    # The syntax tree of a script given as text
    function script:ConvertTo-Ast {
        <#
        .SYNOPSIS
            Converts PowerShell text into its syntax tree.

        .DESCRIPTION
            Parses the text with the PowerShell parser and returns the tree, so that a test can
            pick the node it hands to the function under test. Parse errors are not returned.

        .PARAMETER Text
            The PowerShell text to parse.

        .EXAMPLE
            ConvertTo-Ast 'return 1'

            Returns the syntax tree of a script that holds one return statement.

        .INPUTS
            None.

        .OUTPUTS
            System.Management.Automation.Language.ScriptBlockAst. The tree of the text.
        #>
        [CmdletBinding()]
        [OutputType([System.Management.Automation.Language.ScriptBlockAst])]
        param(
            [string]$Text
        )

        [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null)
    }

    function script:Get-Replacement {
        <#
        .SYNOPSIS
            Gets the replacement Get-IslReturnReplacement gives for the return in a text.

        .DESCRIPTION
            Parses the text, finds its first return statement, searching nested script blocks too,
            and calls the private function inside the module with it.

        .PARAMETER Text
            PowerShell text that holds a return statement.

        .EXAMPLE
            Get-Replacement -Text 'return 1'

            Returns the text that replaces the return statement.

        .INPUTS
            None.

        .OUTPUTS
            System.String. What Get-IslReturnReplacement returns.
        #>
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [string]$Text
        )

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
