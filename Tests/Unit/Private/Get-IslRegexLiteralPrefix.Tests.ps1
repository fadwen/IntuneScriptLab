#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The literal start of an event pattern, which the agent-log reader looks for before it runs
    the pattern.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }
}

Describe 'Get-IslRegexLiteralPrefix' -Tag 'Unit', 'Private' {

    It 'reads <Pattern> as "<Expected>"' -ForEach @(
        @{ Pattern = '^Powershell exit code is (-?\d+)'; Expected = 'Powershell exit code is ' }
        @{ Pattern = 'ESP completed\. Triggering'; Expected = 'ESP completed. Triggering' }
        @{ Pattern = '^error from script =(.*)$'; Expected = 'error from script =' }
        @{ Pattern = 'abc\d+'; Expected = 'abc' }
        @{ Pattern = 'colou?r'; Expected = 'colo' }
        @{ Pattern = 'ab{2}'; Expected = 'a' }
        @{ Pattern = '(start)'; Expected = '' }
        @{ Pattern = 'ends with a backslash\'; Expected = 'ends with a backslash' }
        @{ Pattern = 'Script failed|Script timed out'; Expected = '' }
        @{ Pattern = '^abc|def'; Expected = '' }
        @{ Pattern = 'abc(def|ghi)'; Expected = 'abc' }
        @{ Pattern = 'abc[|]def'; Expected = 'abc' }
        @{ Pattern = 'abc\|def'; Expected = 'abc|def' }
    ) {
        $parameters = @{ Pattern = $Pattern }
        $prefix = InModuleScope IntuneScriptLab -Parameters $parameters {
            Get-IslRegexLiteralPrefix -Pattern $Pattern
        }

        $prefix | Should-Be $Expected
    }

    It 'gives text that every message the pattern matches contains' {
        $pattern = '^Powershell exit code is (-?\d+)'
        $prefix = InModuleScope IntuneScriptLab -Parameters @{ Pattern = $pattern } {
            Get-IslRegexLiteralPrefix -Pattern $Pattern
        }

        'Powershell exit code is -1' -match $pattern | Should-BeTrue
        'Powershell exit code is -1'.Contains($prefix) | Should-BeTrue
    }

    It 'gives no text that a match of the second alternative lacks' {
        $pattern = 'Script failed|Script timed out'
        $prefix = InModuleScope IntuneScriptLab -Parameters @{ Pattern = $pattern } {
            Get-IslRegexLiteralPrefix -Pattern $Pattern
        }

        'Script timed out' -match $pattern | Should-BeTrue
        'Script timed out'.Contains($prefix) | Should-BeTrue
    }
}
