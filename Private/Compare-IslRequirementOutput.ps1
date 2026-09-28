function Compare-IslRequirementOutput {
    <#
    .SYNOPSIS
        Applies a Win32 requirement rule to a script's captured run the way the agent was observed to.

    .DESCRIPTION
        Observed on the test devices (W32-REQ-* experiments): the rule is evaluated only when the
        script exits 0 and writes nothing to stderr; the whole stdout, minus its final line break,
        is the value compared, so a second line or trailing spaces never match (Write-Host text
        counts, as it does for detection); string comparison ignores case; integer, float,
        version, boolean and dateTime outputs are parsed as that type and an unparseable output
        fails the rule.

    .PARAMETER StdOut
        The captured standard output.

    .PARAMETER StdErr
        The captured standard error.

    .PARAMETER ExitCode
        The script's exit code; $null when it was killed.

    .PARAMETER TimedOut
        Whether the script was killed at the timeout.

    .PARAMETER OutputType
        The rule's output data type: String, DateTime, Integer, Float, Version or Boolean.

    .PARAMETER Operator
        Equal, NotEqual, GreaterThan, GreaterThanOrEqual, LessThan or LessThanOrEqual.

    .PARAMETER Value
        The rule's comparison value, as typed in the portal.

    .EXAMPLE
        $ruleSplat = @{ OutputType = 'Version'; Operator = 'GreaterThanOrEqual'; Value = '2.9.0' }
        Compare-IslRequirementOutput -StdOut "2.10.0`r`n" -ExitCode 0 @ruleSplat

        Met, because the output is parsed as a version rather than compared as text.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.RequirementVerdict')]
    param(
        [AllowEmptyString()]
        [string]$StdOut = '',

        [AllowEmptyString()]
        [string]$StdErr = '',

        [AllowNull()]
        [nullable[int]]$ExitCode,

        [bool]$TimedOut,

        [Parameter(Mandatory)]
        [ValidateSet('String', 'DateTime', 'Integer', 'Float', 'Version', 'Boolean')]
        [string]$OutputType,

        [Parameter(Mandatory)]
        [ValidateSet('Equal', 'NotEqual', 'GreaterThan', 'GreaterThanOrEqual', 'LessThan', 'LessThanOrEqual')]
        [string]$Operator,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value
    )

    # Only the final line break is removed, CRLF from Write-Output or the bare LF Write-Host ends
    # with (both met the rule on the device); "ok   " and "first`r`nok" both failed
    $output = $StdOut -replace '\r?\n\z', ''
    $verdict = [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.RequirementVerdict'
        Met        = $false
        Output     = $output
        Reason     = ''
    }

    if ($TimedOut) {
        $verdict.Reason = 'Timed out; the agent kills the script at its 60-minute timeout and the rule fails'
        return $verdict
    }
    if ($ExitCode -ne 0) {
        $verdict.Reason = "Exit code ${ExitCode}: the output is only evaluated on exit 0, so the rule fails"
        return $verdict
    }
    if (-not [string]::IsNullOrWhiteSpace($StdErr)) {
        $verdict.Reason = 'Output on stderr: the rule fails even with exit 0 and matching stdout'
        return $verdict
    }

    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $parsed = $null
    $expected = $null
    switch ($OutputType) {
        'String' {
            $parsed = $output
            $expected = $Value
        }
        'Integer' {
            $number = 0L
            if (-not [long]::TryParse($output.Trim(), [ref]$number)) {
                $verdict.Reason = "Output '$output' is not an integer, so the rule fails"
                return $verdict
            }
            $parsed = $number
            if (-not [long]::TryParse($Value.Trim(), [ref]$number)) {
                $verdict.Reason = "Comparison value '$Value' is not an integer, so the rule fails"
                return $verdict
            }
            $expected = $number
        }
        'Float' {
            $number = 0.0
            $style = [System.Globalization.NumberStyles]::Float
            if (-not [double]::TryParse($output.Trim(), $style, $culture, [ref]$number)) {
                $verdict.Reason = "Output '$output' is not a number, so the rule fails"
                return $verdict
            }
            $parsed = $number
            if (-not [double]::TryParse($Value.Trim(), $style, $culture, [ref]$number)) {
                $verdict.Reason = "Comparison value '$Value' is not a number, so the rule fails"
                return $verdict
            }
            $expected = $number
        }
        'Version' {
            $version = $null
            if (-not [version]::TryParse($output.Trim(), [ref]$version)) {
                $verdict.Reason = "Output '$output' is not a version (a.b[.c[.d]]), so the rule fails"
                return $verdict
            }
            $parsed = $version
            if (-not [version]::TryParse($Value.Trim(), [ref]$version)) {
                $verdict.Reason = "Comparison value '$Value' is not a version, so the rule fails"
                return $verdict
            }
            $expected = $version
        }
        'Boolean' {
            $flag = $false
            if (-not [bool]::TryParse($output.Trim(), [ref]$flag)) {
                $verdict.Reason = "Output '$output' is not True or False, so the rule fails"
                return $verdict
            }
            $parsed = $flag
            if (-not [bool]::TryParse($Value.Trim(), [ref]$flag)) {
                $verdict.Reason = "Comparison value '$Value' is not True or False, so the rule fails"
                return $verdict
            }
            $expected = $flag
            if ($Operator -notin 'Equal', 'NotEqual') {
                $verdict.Reason = "Operator $Operator does not apply to a boolean, so the rule fails"
                return $verdict
            }
        }
        'DateTime' {
            $stamp = [datetime]::MinValue
            $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor
                [System.Globalization.DateTimeStyles]::AdjustToUniversal
            if (-not [datetime]::TryParse($output.Trim(), $culture, $styles, [ref]$stamp)) {
                $verdict.Reason = "Output '$output' is not a date/time, so the rule fails"
                return $verdict
            }
            $parsed = $stamp
            if (-not [datetime]::TryParse($Value.Trim(), $culture, $styles, [ref]$stamp)) {
                $verdict.Reason = "Comparison value '$Value' is not a date/time, so the rule fails"
                return $verdict
            }
            $expected = $stamp
        }
    }

    $comparison = if ($OutputType -eq 'String') {
        [string]::Compare($parsed, $expected, [System.StringComparison]::InvariantCultureIgnoreCase)
    }
    elseif ($OutputType -eq 'Boolean') {
        if ($parsed -eq $expected) { 0 } else { 1 }
    }
    else { $parsed.CompareTo($expected) }

    $verdict.Met = switch ($Operator) {
        'Equal' { $comparison -eq 0 }
        'NotEqual' { $comparison -ne 0 }
        'GreaterThan' { $comparison -gt 0 }
        'GreaterThanOrEqual' { $comparison -ge 0 }
        'LessThan' { $comparison -lt 0 }
        'LessThanOrEqual' { $comparison -le 0 }
    }
    $relation = if ($verdict.Met) { 'meets' } else { 'does not meet' }
    $verdict.Reason = "Output '$output' $relation $OutputType $Operator '$Value'"
    $verdict
}
