function Read-IslFilterValue {
    <#
    .SYNOPSIS
    Reads the value after an operator in an assignment filter rule.

    .DESCRIPTION
    For the assignment filter parser. The value at the parser's cursor is a double-quoted string,
    a list of such strings in brackets, $null or a bare version, and the cursor moves past it.
    It is checked against what the property and the operator accept: a list only with -in and
    -notIn, $null only with -eq and -ne and never on a version property, a version property only
    with a version of 2 to 4 numeric parts, and no empty string. A value that is not allowed
    records the failure in the parser and returns nothing.

    A value that a Windows device never reports for a property with a fixed set of values, and
    -contains with a value of only white space (FLT-W27, FLT-Y03), add a warning instead, because
    the clause then never matches or matches every device.

    .PARAMETER Parser
    The parser state from New-IslFilterParser, with its cursor on the value.

    .PARAMETER Property
    The property the clause compares, an entry of Get-IslFilterProperty.

    .PARAMETER Operator
    The clause's operator without a dash, such as eq or in.

    .EXAMPLE
    Read-IslFilterValue -Parser $parser -Property $properties['devicename'] -Operator 'eq'

    'LAB-PC-01' for the value "LAB-PC-01", with the cursor past it.

    .INPUTS
    None.

    .OUTPUTS
    System.String. The value or each entry of a list; $null for the value $null, and nothing for
    a value that is not allowed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Parser,

        [Parameter(Mandatory)]
        [hashtable]$Property,

        [Parameter(Mandatory)]
        [string]$Operator
    )

    $token = Get-IslFilterToken -Parser $Parser
    if (-not $token) {
        Add-IslFilterParseError -Parser $Parser -Message "expected a value after -$Operator at the end of the rule"
        return
    }
    $value = $null
    $kind = ''
    $where = "(position $($token.Position))"
    switch ($token.Type) {
        'string' {
            $value = $token.Text
            $kind = 'String'
            $Parser.Pos++
        }
        'word' {
            if ($token.Text -in '$null', 'null') {
                $kind = 'Null'
            } elseif ($token.Text -match '^\d+(\.\d+)*$') {
                $value = $token.Text
                $kind = 'Version'
            } else {
                Add-IslFilterParseError -Parser $Parser -Message (
                    "the value $($token.Text) must be in double quotes $where")
                return
            }
            $Parser.Pos++
        }
        'lbracket' {
            $Parser.Pos++
            $items = [System.Collections.Generic.List[string]]::new()
            while ($true) {
                $item = Get-IslFilterToken -Parser $Parser
                if (-not $item) {
                    Add-IslFilterParseError -Parser $Parser -Message (
                        "the list opened at position $($token.Position) is not closed")
                    return
                }
                if ($item.Type -eq 'rbracket') {
                    $Parser.Pos++
                    break
                }
                if ($item.Type -ne 'string') {
                    Add-IslFilterParseError -Parser $Parser -Message ("a list holds double-quoted strings " +
                        "only; found '$($item.Text)' at position $($item.Position)")
                    return
                }
                $items.Add($item.Text)
                $Parser.Pos++
                $next = Get-IslFilterToken -Parser $Parser
                if ($next -and $next.Type -eq 'comma') {
                    $Parser.Pos++
                } elseif ($next -and $next.Type -ne 'rbracket') {
                    if (Test-IslFilterEscapedQuote -Previous $item -Next $next) {
                        Add-IslFilterEscapeError -Parser $Parser -Previous $item
                    } else {
                        Add-IslFilterParseError -Parser $Parser -Message (
                            "expected ',' or ']' at position $($next.Position), found '$($next.Text)'")
                    }
                    return
                }
            }
            if ($items.Count -eq 0) {
                Add-IslFilterParseError -Parser $Parser -Message "the list at position $($token.Position) is empty"
                return
            }
            $value = $items.ToArray()
            $kind = 'List'
        }
        default {
            Add-IslFilterParseError -Parser $Parser -Message (
                "expected a value after -$Operator $where, found '$($token.Text)'")
            return
        }
    }

    $isList = $Operator -in 'in', 'notIn'
    $problem = $null
    if ($kind -eq 'List' -and -not $isList) {
        $problem = "-$Operator takes a single value; a list needs -in or -notIn $where"
    } elseif ($kind -eq 'Null' -and $Operator -notin 'eq', 'ne') {
        $problem = "`$null is accepted with -eq and -ne only $where"
    } elseif ($kind -eq 'Null' -and $Property.Kind -eq 'Version') {
        $problem = "device.$($Property.Name) cannot be compared with `$null $where"
    } elseif ($Property.Kind -eq 'Version' -and $kind -eq 'List') {
        $problem = "device.$($Property.Name) takes a single version, not a list $where"
    } elseif ($Property.Kind -eq 'Version' -and $kind -in 'String', 'Version' -and
        "$value".Trim() -notmatch '^\d+(\.\d+){1,3}$') {
        $problem = "'$value' is not a version of 2 to 4 numeric parts such as 10.0.22631.3235 $where"
    } elseif ($Property.Kind -ne 'Version' -and $kind -eq 'Version') {
        $problem = "the value $value must be in double quotes $where"
    } elseif ($kind -eq 'String' -and $value.Length -eq 0) {
        $problem = "an empty string is refused $where; compare with `$null for a device without a value"
    }
    if ($null -ne $problem) {
        Add-IslFilterParseError -Parser $Parser -Message $problem
        return
    }

    if ($Property['Values'] -and $Operator -in 'eq', 'in', 'ne', 'notIn') {
        # -eq and -in with such a value match nobody; -ne and -notIn match every device
        $positive = $Operator -in 'eq', 'in'
        foreach ($item in @($value)) {
            if ($null -ne $item -and "$item".Trim() -notin $Property['Values']) {
                $warningKind = if ($positive) { 'NeverMatches' } else { 'AlwaysMatches' }
                $effect = if ($positive) { 'never matches' } else { 'matches every device' }
                $message = ("'$item' is not a value a Windows device reports for device.$($Property.Name) " +
                    "($($Property['Values'] -join ', ')); the clause at character $($token.Position) $effect")
                Add-IslFilterWarning -Parser $Parser -Kind $warningKind -Message $message
            }
        }
    }
    if ($Operator -eq 'contains' -and $kind -eq 'String' -and "$value".Trim().Length -eq 0) {
        # The evaluator trims the value to nothing, and every name contains an empty string:
        # -contains " " matched every device (FLT-W27, FLT-Y03)
        $message = ("'$value' is only whitespace, which the evaluator trims to nothing, and every value " +
            "contains that; the clause at character $($token.Position) matches every device")
        Add-IslFilterWarning -Parser $Parser -Kind 'AlwaysMatches' -Message $message
    }
    $value
}
