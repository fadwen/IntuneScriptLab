#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The typed comparison behind the file, registry and product code rules, each case an observed
    outcome from the W32-FILE-*, W32-REG-* and W32-MSI-* experiments.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force

    function Compare-Value {
        param([hashtable]$Parameters)
        InModuleScope IntuneScriptLab -Parameters @{ P = $Parameters } { Compare-IslRuleValue @P }
    }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Compare-IslRuleValue' -Tag 'Unit', 'Private' {

    It 'compares strings case-insensitively (W32-REG-STR-CASE)' {
        $result = Compare-Value @{ Actual = 'IntuneScriptLab'; Expected = 'intunescriptlab'; Type = 'String'
            Operator = 'Equal' }
        $result.Met | Should-BeTrue
        $result.PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.RuleComparison'
        $other = Compare-Value @{ Actual = 'IntuneScriptLab'; Expected = 'other'; Type = 'String'
            Operator = 'Equal' }
        $other.Met | Should-BeFalse
    }

    It 'compares versions as versions, so 10.0.1 is above 9.0 (W32-REG-VER-GE, W32-FILE-VER-GE)' {
        $ge = Compare-Value @{ Actual = '10.0.1'; Expected = '9.0'; Type = 'Version'
            Operator = 'GreaterThanOrEqual' }
        $ge.Met | Should-BeTrue
        (Compare-Value @{ Actual = '10.0.1'; Expected = '9.0'; Type = 'Version'; Operator = 'LessThan' }).Met |
            Should-BeFalse
        $msi = Compare-Value @{ Actual = '110.0.2'; Expected = '99.0.0'; Type = 'Version'
            Operator = 'GreaterThanOrEqual' }
        $msi.Met | Should-BeTrue
    }

    It 'falls back to a text comparison when either side is not a version, and says so' {
        $result = Compare-Value @{ Actual = 'beta'; Expected = '9.0'; Type = 'Version'; Operator = 'GreaterThan' }
        $result.Met | Should-BeTrue
        $result.Reason | Should-BeLikeString '*compared as text*'
    }

    It 'parses integers from numbers and from strings (W32-REG-INT-GT, W32-REG-INT-ONSZ)' {
        (Compare-Value @{ Actual = 42; Expected = '40'; Type = 'Integer'; Operator = 'GreaterThan' }).Met |
            Should-BeTrue
        (Compare-Value @{ Actual = '42'; Expected = '40'; Type = 'Integer'; Operator = 'GreaterThan' }).Met |
            Should-BeTrue
        (Compare-Value @{ Actual = 42; Expected = '50'; Type = 'Integer'; Operator = 'GreaterThan' }).Met |
            Should-BeFalse
    }

    It 'is not met when the integer does not parse, with the reason' {
        $result = Compare-Value @{ Actual = 'forty'; Expected = '40'; Type = 'Integer'; Operator = 'Equal' }
        $result.Met | Should-BeFalse
        $result.Reason | Should-BeLikeString "*'forty' is not an integer*"
    }

    It 'compares dates in UTC from strings and DateTime values (W32-FILE-DATE-GT)' {
        $stamp = [datetime]::new(2024, 6, 15, 12, 0, 0, [DateTimeKind]::Utc)
        (Compare-Value @{ Actual = $stamp; Expected = '2024-01-01T00:00:00Z'; Type = 'DateTime'
            Operator = 'GreaterThan' }).Met | Should-BeTrue
        (Compare-Value @{ Actual = '2024-06-15'; Expected = '2024-01-01T00:00:00Z'; Type = 'DateTime'
            Operator = 'LessThan' }).Met | Should-BeFalse
    }

    It 'applies every operator: <Operator> on 5 vs 3 is <Expected>' -ForEach @(
        @{ Operator = 'Equal';              Expected = $false }
        @{ Operator = 'NotEqual';           Expected = $true }
        @{ Operator = 'GreaterThan';        Expected = $true }
        @{ Operator = 'GreaterThanOrEqual'; Expected = $true }
        @{ Operator = 'LessThan';           Expected = $false }
        @{ Operator = 'LessThanOrEqual';    Expected = $false }
    ) {
        (Compare-Value @{ Actual = 5; Expected = '3'; Type = 'Integer'; Operator = $Operator }).Met |
            Should-Be $Expected
    }
}
