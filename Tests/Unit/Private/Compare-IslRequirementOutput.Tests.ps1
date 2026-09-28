#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The requirement-rule evaluation, each case an observed outcome from the W32-REQ-* experiments
    (Validation\Findings.md, "Win32 requirement scripts"): whole stdout minus the final line
    break, case-insensitive strings, typed comparisons, and exit code / stderr gating.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')

    function Compare-Output {
        param([hashtable]$Parameters)
        $defaults = @{ StdOut = ''; StdErr = ''; ExitCode = 0; TimedOut = $false }
        foreach ($key in $Parameters.Keys) { $defaults[$key] = $Parameters[$key] }
        InModuleScope IntuneScriptLab -Parameters @{ P = $defaults } {
            Compare-IslRequirementOutput @P
        }
    }
    # A string rule "equal ok", the round-4 baseline, with the output under test
    function Compare-Ok {
        param([string]$StdOut, [hashtable]$More = @{})
        $rule = @{ StdOut = $StdOut; OutputType = 'String'; Operator = 'Equal'; Value = 'ok' }
        foreach ($key in $More.Keys) { $rule[$key] = $More[$key] }
        Compare-Output $rule
    }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Compare-IslRequirementOutput' -Tag 'Unit', 'Private' {

    Context 'Gating on exit code and stderr' {
        It 'is met by exit 0, matching stdout and no stderr (W32-REQ-BASE)' {
            $verdict = Compare-Ok "ok`r`n"
            $verdict.Met | Should-BeTrue
            $verdict.Output | Should-Be 'ok'
            $verdict.PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.RequirementVerdict'
        }

        It 'fails on a non-zero exit without looking at the output (W32-REQ-EXIT1)' {
            $verdict = Compare-Ok "ok`r`n" @{ ExitCode = 1 }
            $verdict.Met | Should-BeFalse
            $verdict.Reason | Should-BeLikeString 'Exit code 1:*'
        }

        It 'fails on stderr even with exit 0 and matching output (W32-REQ-STDERR)' {
            $verdict = Compare-Ok "ok`r`n" @{ StdErr = 'oops' }
            $verdict.Met | Should-BeFalse
            $verdict.Reason | Should-BeLikeString '*stderr*'
        }

        It 'fails on a timeout' {
            $verdict = Compare-Ok '' @{ TimedOut = $true; ExitCode = $null }
            $verdict.Met | Should-BeFalse
            $verdict.Reason | Should-BeLikeString 'Timed out*'
        }
    }

    Context 'String rules' {
        It 'ignores case (W32-REQ-CASE)' {
            (Compare-Ok "OK`r`n").Met | Should-BeTrue
        }

        It 'compares the whole output, so a second line never matches (W32-REQ-LASTLINE, FIRSTLINE)' {
            (Compare-Ok "first`r`nok`r`n").Met | Should-BeFalse
            (Compare-Ok "ok`r`nsecond`r`n").Met | Should-BeFalse
        }

        It 'does not trim spaces, only the final line break (W32-REQ-TRAIL)' {
            (Compare-Ok "ok   `r`n").Met | Should-BeFalse
            (Compare-Ok "ok`r`n`r`n").Met | Should-BeFalse
            (Compare-Ok 'ok').Met | Should-BeTrue
        }

        It 'is met by a Write-Host line, which ends with a bare LF (W32-REQ-HOST)' {
            $verdict = Compare-Ok "ok`n"
            $verdict.Met | Should-BeTrue
            $verdict.Output | Should-Be 'ok'
        }

        It 'fails with nothing on stdout (W32-REQ-NOOUT)' {
            (Compare-Ok '').Met | Should-BeFalse
        }

        It 'supports NotEqual (W32-REQ-NOTEQ)' {
            (Compare-Ok "ok`r`n" @{ Operator = 'NotEqual'; Value = 'bad' }).Met | Should-BeTrue
        }
    }

    Context 'Typed rules' {
        It 'compares <Type>: <Output> <Operator> <Value> is <Expected>' -ForEach @(
            @{ Type='Integer'; Output='5'; Operator='GreaterThan'; Value='3'; Expected=$true }
            @{ Type='Integer'; Output='five'; Operator='GreaterThan'; Value='3'; Expected=$false }
            @{ Type='Integer'; Output='10'; Operator='LessThan'; Value='9'; Expected=$false }
            @{ Type='Float'; Output='1.5'; Operator='GreaterThan'; Value='1.25'; Expected=$true }
            @{ Type='Version'; Output='2.10.0'; Operator='GreaterThanOrEqual'; Value='2.9.0'; Expected=$true }
            @{ Type='Version'; Output='2.10.0'; Operator='LessThanOrEqual'; Value='2.9.0'; Expected=$false }
            @{ Type='Boolean'; Output='True'; Operator='Equal'; Value='true'; Expected=$true }
            @{ Type='Boolean'; Output='yes'; Operator='Equal'; Value='true'; Expected=$false }
            @{ Type='DateTime'; Output='2026-01-15'; Operator='GreaterThan'; Value='2026-01-01T00:00:00Z'
                Expected=$true }
            @{ Type='DateTime'; Output='soon'; Operator='GreaterThan'; Value='2026-01-01'; Expected=$false }
        ) {
            $rule = @{ StdOut = "$Output`r`n"; OutputType = $Type; Operator = $Operator; Value = $Value }
            (Compare-Output $rule).Met | Should-Be $Expected
        }

        It 'explains an output that does not parse as the type (W32-REQ-INTBAD)' {
            $rule = @{ StdOut = "five`r`n"; OutputType = 'Integer'; Operator = 'GreaterThan'; Value = '3' }
            (Compare-Output $rule).Reason | Should-BeLikeString "Output 'five' is not an integer*"
        }

        It 'rejects ordering operators on a boolean' {
            $rule = @{ StdOut = "True`r`n"; OutputType = 'Boolean'; Operator = 'GreaterThan'; Value = 'true' }
            $verdict = Compare-Output $rule
            $verdict.Met | Should-BeFalse
            $verdict.Reason | Should-BeLikeString '*does not apply to a boolean*'
        }

        It 'parses numbers with the invariant culture' {
            $rule = @{ StdOut = "1.5`r`n"; OutputType = 'Float'; Operator = 'Equal'; Value = '1.50' }
            (Compare-Output $rule).Met | Should-BeTrue
        }
    }
}
