function Test-IslFilterClause {
    <#
    .SYNOPSIS
    Tells whether one clause of an assignment filter rule matches the facts of a device.

    .DESCRIPTION
    The clause is one comparison that ConvertFrom-IslFilterRule read, such as
    (device.osVersion -ge "10.0.22000"). Its property is looked up in the facts; a property the
    device does not have compares as an empty text. Text comparisons with eq, ne, in and notIn
    are those of PowerShell, which ignore letter case, and startsWith, contains and notContains
    ignore it as well. A clause of the Version kind compares with Compare-IslFilterVersion for
    eq, ne, gt, ge, lt and le; when one of its sides is not a version, eq does not match, ne
    does, and gt, ge, lt and le do not.

    The clause is changed in place: Actual is set to the device's value, or $null, and Matched
    to the result, so that the result object of Test-IntuneAssignmentFilter shows what each
    clause saw.

    .PARAMETER Clause
    The clause, an IntuneScriptLab.FilterClause with Property, Operator, Value and Kind.

    .PARAMETER Facts
    The device's facts, by property name, compared without regard to letter case.

    .EXAMPLE
    Test-IslFilterClause -Clause $parsed.Clauses[0] -Facts $facts

    $true when the device's value satisfies the first clause of the rule.

    .INPUTS
    None.

    .OUTPUTS
    System.Boolean.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [PSTypeName('IntuneScriptLab.FilterClause')]
        [psobject]$Clause,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.Dictionary[string, object]]$Facts
    )

    $raw = if ($Facts.ContainsKey($Clause.Property)) { $Facts[$Clause.Property] } else { $null }
    $actual = if ($null -eq $raw) { '' } else { "$raw" }
    $Clause.Actual = if ($null -eq $raw) { $null } else { "$raw" }
    $values = @(foreach ($item in @($Clause.Value)) { if ($null -ne $item) { "$item".Trim() } })
    $expected = if ($values.Count) { $values[0] } else { '' }
    $ignoreCase = [System.StringComparison]::OrdinalIgnoreCase
    $order = $null
    if ($Clause.Kind -eq 'Version') { $order = Compare-IslFilterVersion -Actual $actual -Expected $expected }
    $matched = switch ($Clause.Operator) {
        'eq' { if ($Clause.Kind -eq 'Version') { $order -eq 0 } else { $actual -eq $expected } }
        'ne' { if ($Clause.Kind -eq 'Version') { $order -ne 0 } else { $actual -ne $expected } }
        'in' { $values -contains $actual }
        'notIn' { $values -notcontains $actual }
        'startsWith' { $actual.StartsWith($expected, $ignoreCase) }
        'contains' { $actual.IndexOf($expected, $ignoreCase) -ge 0 }
        'notContains' { $actual.IndexOf($expected, $ignoreCase) -lt 0 }
        'gt' { $null -ne $order -and $order -gt 0 }
        'ge' { $null -ne $order -and $order -ge 0 }
        'lt' { $null -ne $order -and $order -lt 0 }
        'le' { $null -ne $order -and $order -le 0 }
    }
    $Clause.Matched = [bool]$matched
    $Clause.Matched
}
