#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The tokens of an assignment filter rule and the state the parser starts from.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    function script:New-Parser {
        <#
        .SYNOPSIS
            Creates a filter rule parser with the module's private New-IslFilterParser.

        .DESCRIPTION
            Calls New-IslFilterParser inside the module, where the private function is visible,
            and returns the parser with its tokens, position and any error.

        .PARAMETER Rule
            The text of the filter rule.

        .EXAMPLE
            New-Parser -Rule '(device.deviceName -eq "X")'

            Returns the parser for a rule with one clause.

        .INPUTS
            None.

        .OUTPUTS
            System.Collections.Hashtable. The parser state.
        #>
        [CmdletBinding()]
        [OutputType([hashtable])]
        param(
            [string]$Rule
        )

        InModuleScope IntuneScriptLab -Parameters @{ Rule = $Rule } { New-IslFilterParser -Rule $Rule }
    }
}

Describe 'New-IslFilterParser' -Tag 'Unit', 'Private' {

    It 'splits a rule into tokens with their positions' {
        $parser = New-Parser -Rule '(device.osVersion -in ["a", "b"])'

        $types = @($parser.Tokens | ForEach-Object { $_.Type })
        $types | Should-BeCollection -Count 9
        $types -join ' ' | Should-Be 'lparen word word lbracket string comma string rbracket rparen'
        $parser.Tokens[1].Text | Should-Be 'device.osVersion'
        $parser.Tokens[1].Position | Should-Be 2
        $parser.Tokens[1].End | Should-Be 17
        $parser.Tokens[4].Text | Should-Be 'a'
    }

    It 'starts with the cursor at the first token, no failure, no clauses and no warnings' {
        $parser = New-Parser -Rule '(device.deviceName -eq "X")'

        $parser.Pos | Should-Be 0
        $parser.Error | Should-BeNull
        $parser.Rule | Should-Be '(device.deviceName -eq "X")'
        $parser.Clauses.Count | Should-Be 0
        $parser.Warnings.Count | Should-Be 0
        $parser.Properties['devicename'].Name | Should-Be 'deviceName'
        $parser.Operators | Should-ContainCollection @('eq', 'startsWith', 'le')
        $parser.RefusedOperators.ContainsKey('endswith') | Should-BeTrue
    }

    It 'records an empty rule as the failure' {
        (New-Parser -Rule '   ').Error | Should-Be 'Filter rule: the rule is empty'
    }

    It 'stops at a character no token starts with, such as a quote that is not closed' {
        $parser = New-Parser -Rule '(device.deviceName -eq "X'

        $parser.Error | Should-Be "Filter rule: unexpected character '`"' at position 24"
        $parser.Tokens.Count | Should-Be 3
    }
}
