function ConvertFrom-IslFilterRule {
    <#
    .SYNOPSIS
        Parses an assignment filter rule, refusing what the service refuses.

    .DESCRIPTION
        The rule syntax of Intune assignment filters, as the reference documents it and as the
        service's validateFilter accepted or refused it in the lab (Validation\Findings.md,
        "Assignment filter rules"):

        - A clause is device.<property> <operator> <value>, in parentheses or not; clauses join
          with and / or (with or without a leading dash, any casing), and binds tighter than or,
          parentheses nest. Property names, operators and connectors are case-insensitive.
        - Values are double-quoted strings, a bracketed list of them for -in / -notIn (a trailing
          comma is tolerated; a single string is accepted as a one-item list), $null or null with
          -eq / -ne, or a bare 2-to-4-part version for operatingSystemVersion. Single quotes,
          unquoted words, numbers, escaped quotes, an empty string and an empty list are refused.
        - Each property allows the operators the reference lists for it; -startsWith on a version,
          -gt on a string, -contains on an enumerated property, and the operators the reference
          does not have (not, endsWith, notStartsWith, equals) are refused.

        A refused rule is reported on the result's Error property rather than thrown: a throw
        unwinding the parser's frames leaves one error record per frame in the caller's
        -ErrorVariable, and the public command wants to write exactly one. The result carries the
        clauses in order, the tree the evaluator walks, and warnings for rules the service
        accepts but that never match a Windows device: an enumerated value outside the documented
        set (cpuArchitecture "x64", deviceTrustType "Microsoft Entra joined"), a -contains value
        that is only whitespace (the evaluator trims it to nothing, and every name contains that),
        the deprecated osVersion property and the undocumented isTpmAttested.

    .PARAMETER Rule
        The rule text as the portal's rule syntax editor or the Graph assignmentFilter.rule holds it.

    .EXAMPLE
        $rule = '(device.deviceName -startsWith "LAB-") and (device.model -eq "X")'
        (ConvertFrom-IslFilterRule -Rule $rule).Clauses | Format-Table Property, Operator, Value

        Two clauses under an And node; Error is null and there are no warnings.

    .EXAMPLE
        (ConvertFrom-IslFilterRule -Rule '(device.cpuArchitecture -eq "x64")').Warnings

        One warning: the service accepts "x64" but Windows devices report amd64, so the clause never matches.

    .EXAMPLE
        (ConvertFrom-IslFilterRule -Rule "(device.deviceName -eq 'X')").Error

        The message names the position and what the service expects (double quotes).

    .INPUTS
        None.

    .OUTPUTS
        IntuneScriptLab.FilterRule.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.FilterRule')]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Rule
    )

    $parser = New-IslFilterParser -Rule $Rule
    $tree = $null
    if (-not $parser.Error) {
        $tree = Read-IslFilterExpression -Parser $parser
        $rest = Get-IslFilterToken -Parser $parser
        if (-not $parser.Error -and $rest) {
            $previous = $parser.Tokens[$parser.Pos - 1]
            if ($rest.Type -eq 'rparen') {
                Add-IslFilterParseError -Parser $parser -Message "unexpected ')' at position $($rest.Position)"
            } elseif (Test-IslFilterEscapedQuote -Previous $previous -Next $rest) {
                Add-IslFilterEscapeError -Parser $parser -Previous $previous
            } else {
                Add-IslFilterParseError -Parser $parser -Message (
                    "expected 'and' or 'or' before '$($rest.Text)' at position $($rest.Position)")
            }
        }
    }

    [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.FilterRule'
        Rule = $Rule
        Error = $parser.Error
        Tree = if ($parser.Error) { $null } else { $tree }
        Clauses = if ($parser.Error) { @() } else { $parser.Clauses.ToArray() }
        Warnings = if ($parser.Error) { @() } else { $parser.Warnings.ToArray() }
    }
}
