#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The renaming of capturing groups that lets the agent-log reader join every event pattern into
    one expression.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }

    function ConvertTo-Named {
        param([string]$Pattern)
        InModuleScope IntuneScriptLab -Parameters @{ Pattern = $Pattern } {
            ConvertTo-IslNamedGroupPattern -Pattern $Pattern -Prefix 'e3g'
        }
    }
}

Describe 'ConvertTo-IslNamedGroupPattern' -Tag 'Unit', 'Private' {

    It 'names <Count> group(s) in <Pattern>' -ForEach @(
        @{ Pattern = '^exit code is (-?\d+)'; Expected = '^exit code is (?<e3g1>-?\d+)'; Count = 1 }
        @{ Pattern = 'a (b) c (d)'; Expected = 'a (?<e3g1>b) c (?<e3g2>d)'; Count = 2 }
        @{ Pattern = 'x(?:y)(z)'; Expected = 'x(?:y)(?<e3g1>z)'; Count = 1 }
        @{ Pattern = 'x(?<own>y)'; Expected = 'x(?<own>y)'; Count = 0 }
        @{ Pattern = 'a\(b\)'; Expected = 'a\(b\)'; Count = 0 }
        @{ Pattern = 'a[(]b(c)'; Expected = 'a[(]b(?<e3g1>c)'; Count = 1 }
        @{ Pattern = 'plain text'; Expected = 'plain text'; Count = 0 }
    ) {
        $result = ConvertTo-Named -Pattern $Pattern

        $result['Pattern'] | Should-Be $Expected
        $result['Count'] | Should-Be $Count
    }

    It 'leaves a pattern that matches the same text and captures the same values' {
        $pattern = '^write output done\. output = (.*?)(?:\r?\n?, error = (.*))?$'
        $result = ConvertTo-Named -Pattern $pattern
        $text = 'write output done. output = ok, error = bad'

        $original = [regex]::Match($text, $pattern)
        $renamed = [regex]::Match($text, $result['Pattern'])

        $renamed.Success | Should-BeTrue
        $renamed.Groups['e3g1'].Value | Should-Be $original.Groups[1].Value
        $renamed.Groups['e3g2'].Value | Should-Be $original.Groups[2].Value
    }
}
