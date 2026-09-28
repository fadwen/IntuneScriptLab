function Compare-IslRuleValue {
    <#
    .SYNOPSIS
        Compares a value read from the device with a rule's comparison value the way the agent does.

    .DESCRIPTION
        The typed comparison behind the file, registry and product code rules (W32-FILE-*, W32-REG-*,
        W32-MSI-* experiments): strings compare case-insensitively (W32-REG-STR-CASE), integers are
        parsed from whatever the value is, a REG_SZ "42" included (W32-REG-INT-ONSZ), versions are
        compared as versions so 10.0.1 is above 9.0 (W32-REG-VER-GE, W32-FILE-VER-GE, W32-MSI-VER-GE)
        and, as the Graph documentation states, fall back to a string comparison when either side is
        not a version, and dates are compared in UTC (W32-FILE-DATE-GT).

    .PARAMETER Actual
        The value found on the device: a string, number, version or date.

    .PARAMETER Expected
        The rule's comparison value as typed in the portal.

    .PARAMETER Type
        String, Integer, Version or DateTime.

    .PARAMETER Operator
        Equal, NotEqual, GreaterThan, GreaterThanOrEqual, LessThan or LessThanOrEqual.

    .EXAMPLE
        Compare-IslRuleValue -Actual '10.0.1' -Expected '9.0' -Type Version -Operator GreaterThanOrEqual

        Met: the values are compared as versions, not as text.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.RuleComparison')]
    param(
        [AllowNull()]
        $Actual,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Expected,

        [Parameter(Mandatory)]
        [ValidateSet('String', 'Integer', 'Version', 'DateTime')]
        [string]$Type,

        [Parameter(Mandatory)]
        [ValidateSet('Equal', 'NotEqual', 'GreaterThan', 'GreaterThanOrEqual', 'LessThan', 'LessThanOrEqual')]
        [string]$Operator
    )

    $result = [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.RuleComparison'
        Met        = $false
        Actual     = "$Actual"
        Expected   = $Expected
        Reason     = ''
    }
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $left = $null
    $right = $null
    $comparedAs = $Type

    switch ($Type) {
        'String' {
            $left = "$Actual"
            $right = $Expected
        }
        'Integer' {
            $number = 0L
            if ($Actual -is [int] -or $Actual -is [long] -or $Actual -is [uint32] -or $Actual -is [int16]) {
                $left = [long]$Actual
            }
            elseif ([long]::TryParse("$Actual".Trim(), [ref]$number)) { $left = $number }
            else {
                $result.Reason = "Value '$Actual' is not an integer, so the rule is not met"
                return $result
            }
            if (-not [long]::TryParse($Expected.Trim(), [ref]$number)) {
                $result.Reason = "Comparison value '$Expected' is not an integer, so the rule is not met"
                return $result
            }
            $right = $number
        }
        'Version' {
            $version = $null
            if ([version]::TryParse("$Actual".Trim(), [ref]$version)) { $left = $version }
            if ([version]::TryParse($Expected.Trim(), [ref]$version)) { $right = $version }
            if ($null -eq $left -or $null -eq $right) {
                # Graph documents the fallback: a value that is not version-shaped is compared as text
                $left = "$Actual"
                $right = $Expected
                $comparedAs = 'String'
            }
        }
        'DateTime' {
            $stamp = [datetime]::MinValue
            $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor
                [System.Globalization.DateTimeStyles]::AdjustToUniversal
            if ($Actual -is [datetime]) { $left = $Actual.ToUniversalTime() }
            elseif ([datetime]::TryParse("$Actual".Trim(), $culture, $styles, [ref]$stamp)) { $left = $stamp }
            else {
                $result.Reason = "Value '$Actual' is not a date/time, so the rule is not met"
                return $result
            }
            if (-not [datetime]::TryParse($Expected.Trim(), $culture, $styles, [ref]$stamp)) {
                $result.Reason = "Comparison value '$Expected' is not a date/time, so the rule is not met"
                return $result
            }
            $right = $stamp
        }
    }

    $comparison = if ($comparedAs -eq 'String') {
        [string]::Compare($left, $right, [System.StringComparison]::InvariantCultureIgnoreCase)
    }
    else { $left.CompareTo($right) }

    $result.Met = switch ($Operator) {
        'Equal' { $comparison -eq 0 }
        'NotEqual' { $comparison -ne 0 }
        'GreaterThan' { $comparison -gt 0 }
        'GreaterThanOrEqual' { $comparison -ge 0 }
        'LessThan' { $comparison -lt 0 }
        'LessThanOrEqual' { $comparison -le 0 }
    }
    $relation = if ($result.Met) { 'meets' } else { 'does not meet' }
    $fallback = if ($comparedAs -ne $Type) { " (compared as text: not both values are versions)" } else { '' }
    $result.Reason = "'$Actual' $relation $Type $Operator '$Expected'$fallback"
    $result
}
