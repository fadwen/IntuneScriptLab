#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Two assignment filter tokens that are a double quote someone tried to escape (FLT-V44, FLT-V45).
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    # Whether the first two tokens of the text are the escaped quote
    function script:Test-Pair {
        <#
        .SYNOPSIS
            Tests whether the first two tokens of a filter rule escape a quote.

        .DESCRIPTION
            Tokenizes the text with the private New-IslFilterParser inside the module and passes
            its first and second token to Test-IslFilterEscapedQuote.

        .PARAMETER Text
            The text to tokenize. Its first two tokens are tested.

        .EXAMPLE
            Test-Pair -Text '"say ""hi"""'

            Returns $true: the doubled quotes split the value into strings glued together.

        .INPUTS
            None.

        .OUTPUTS
            System.Boolean. The answer of Test-IslFilterEscapedQuote.
        #>
        [CmdletBinding()]
        [OutputType([bool])]
        param(
            [string]$Text
        )

        InModuleScope IntuneScriptLab -Parameters @{ Text = $Text } {
            $tokens = (New-IslFilterParser -Rule $Text).Tokens
            Test-IslFilterEscapedQuote -Previous $tokens[0] -Next $tokens[1]
        }
    }
}

Describe 'Test-IslFilterEscapedQuote' -Tag 'Unit', 'Private' {

    It 'gives <Expected> for <Text>' -ForEach @(
        @{ Text = '"say \"hi\""'; Expected = $true }
        @{ Text = '"say ""hi"""'; Expected = $true }
        @{ Text = '"a" "b"'; Expected = $false }
        @{ Text = '"a\" b'; Expected = $false }
        @{ Text = 'word "b"'; Expected = $false }
    ) {
        Test-Pair -Text $Text | Should-Be $Expected
    }

    It 'gives false when a token is missing' {
        $result = InModuleScope IntuneScriptLab {
            $token = (New-IslFilterParser -Rule '"a"').Tokens[0]
            Test-IslFilterEscapedQuote -Previous $token -Next $null
            Test-IslFilterEscapedQuote -Previous $null -Next $token
        }

        $result | Should-BeCollection @($false, $false)
    }
}
