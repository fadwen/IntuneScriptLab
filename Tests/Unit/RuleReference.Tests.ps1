#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The generated rule reference: docs\Rules.md must match what Build-RuleReference.ps1 produces from
    the current rules (the drift gate), every rule must have a section with at least one finding row,
    and the evidence of every row must cite an experiment or a documented source.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Builder = Join-Path $script:ModuleRoot 'Build\Build-RuleReference.ps1'
    $script:Generated = & $script:Builder -PassThru
    $script:Rules = @(Get-ChildItem (Join-Path $script:ModuleRoot 'Private\Rules\Find-Isl*.ps1') |
        ForEach-Object { $_.BaseName -replace '^Find-', '' } | Sort-Object)
}

Describe 'Build-RuleReference' -Tag 'Unit' {

    It 'documents every rule with at least one finding row' {
        foreach ($rule in $script:Rules) {
            $section = [regex]::Match($script:Generated, "(?s)## $rule\r?\n(.*?)(?=\r?\n## |\z)")
            $section.Success | Should-BeTrue -Because "$rule needs a section"
            $severity = '(?:Error|Warning|Information)(?: or (?:Error|Warning|Information))*'
            @([regex]::Matches($section.Groups[1].Value, "(?m)^\| $severity \|")).Count |
                Should-BeGreaterThan 0 -Because "$rule needs a finding row"
        }
        @([regex]::Matches($script:Generated, '(?m)^## ')).Count | Should-Be $script:Rules.Count
    }

    It 'resolves every message and evidence to text, with placeholders for run-time values' {
        $severity = '(?:Error|Warning|Information)(?: or (?:Error|Warning|Information))*'
        $rows = @([regex]::Matches($script:Generated, "(?m)^\| ($severity) \| (.*?) \| (.*) \|$"))
        $rows.Count | Should-BeGreaterThan 30
        foreach ($row in $rows) {
            $row.Groups[2].Value | Should-NotBeWhiteSpaceString
            $row.Groups[3].Value | Should-NotBeWhiteSpaceString
            # An unresolved expression would leave a variable or subexpression behind; a literal
            # "$<value>" (the name of an environment variable in a message) is fine
            $row.Groups[1].Value | Should-NotBeLikeString '*<*'
            $row.Groups[2].Value | Should-NotBeLikeString '*$[a-zA-Z_(]*'
            $row.Groups[3].Value | Should-NotBeLikeString '*$[a-zA-Z_(]*'
        }
    }

    It 'cites an experiment or Microsoft Learn in the evidence of every rule' {
        foreach ($rule in $script:Rules) {
            $section = [regex]::Match($script:Generated, "(?s)## $rule\r?\n(.*?)(?=\r?\n## |\z)").Groups[1].Value
            $cited = $section -match '\b(REM|PS|W32|FLT|ESP|ASSIGN|PROBE)-[A-Z0-9-]+\b' -or
                $section -match 'Microsoft Learn|host survey|ARM64 host'
            $cited | Should-BeTrue -Because "$rule needs evidence that cites its source"
        }
    }

    It 'matches the committed docs\Rules.md (run Build\Build-RuleReference.ps1 after changing a rule)' {
        $committed = [System.IO.File]::ReadAllText((Join-Path $script:ModuleRoot 'docs\Rules.md'))
        ($committed -replace "`r`n", "`n") | Should-Be ($script:Generated -replace "`r`n", "`n")
    }
}
