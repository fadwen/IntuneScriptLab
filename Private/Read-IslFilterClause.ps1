function Read-IslFilterClause {
    <#
    .SYNOPSIS
    Reads one comparison of an assignment filter rule, such as device.deviceName -eq "X".

    .DESCRIPTION
    For the assignment filter parser. At the parser's cursor it reads a property of the form
    device.<name>, an operator and its value (through Read-IslFilterValue), and moves the cursor
    past them. The property must be one of Get-IslFilterProperty, case aside, and the operator
    one that the service accepts on that property; app.* properties, other entities, refused
    operators such as -endsWith and not, and connectors where a clause belongs each record the
    reason in the parser and return nothing.

    A deprecated or undocumented property adds a warning. The clause is added to the parser's
    Clauses as an IntuneScriptLab.FilterClause, with its text taken from the rule, and returned
    as a node of the tree that Test-IslFilterNode evaluates.

    .PARAMETER Parser
    The parser state from New-IslFilterParser, with its cursor on the property.

    .EXAMPLE
    Read-IslFilterClause -Parser $parser

    @{ Type = 'Clause'; Clause = <the clause> } for device.deviceName -eq "X".

    .INPUTS
    None.

    .OUTPUTS
    System.Collections.Hashtable. A Clause node, or nothing when the clause does not parse.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Parser
    )

    $token = Get-IslFilterToken -Parser $Parser
    if (-not $token) {
        Add-IslFilterParseError -Parser $Parser -Message (
            'expected a clause such as (device.deviceName -eq "X") at the end')
        return
    }
    $at = "at position $($token.Position)"
    $bare = ($token.Text -replace '^-', '').ToLowerInvariant()
    $propertyMatch = [regex]::Match($token.Text, '^(?<entity>[A-Za-z]+)\.(?<name>[A-Za-z]+)$')
    $entity = $propertyMatch.Groups['entity'].Value
    $name = $propertyMatch.Groups['name'].Value
    $property = $null
    if ($propertyMatch.Success -and $entity -eq 'device') {
        $property = $Parser.Properties[$name.ToLowerInvariant()]
    }
    $problem = $null
    if ($token.Type -ne 'word') {
        $problem = "expected a property such as device.deviceName $at, found '$($token.Text)'"
    } elseif ($bare -in 'and', 'or') {
        $problem = "expected a clause before '$($token.Text)' $at"
    } elseif ($bare -in 'not', '!') {
        $problem = "$($Parser.RefusedOperators[$bare]) ($at)"
    } elseif (-not $propertyMatch.Success) {
        $problem = "'$($token.Text)' $at is not a property; a clause starts with device.<property>"
    } elseif ($entity -eq 'app') {
        $problem = "$($token.Text) $at is a managed app property; a device filter reads device.* properties"
    } elseif ($entity -ne 'device') {
        $problem = "unknown entity '$entity' $at; a device filter reads device.* properties"
    } elseif (-not $property) {
        $known = ($Parser.Properties.Values | ForEach-Object { $_.Name } | Sort-Object) -join ', '
        $problem = "unknown property device.$name $at. Windows device filters know: $known"
    }
    if ($null -ne $problem) {
        Add-IslFilterParseError -Parser $Parser -Message $problem
        return
    }
    $Parser.Pos++

    $operatorToken = Get-IslFilterToken -Parser $Parser
    if (-not $operatorToken -or $operatorToken.Type -ne 'word') {
        $found = if ($operatorToken) { "found '$($operatorToken.Text)'" } else { 'the rule ends' }
        Add-IslFilterParseError -Parser $Parser -Message (
            "expected an operator after device.$($property.Name); $found")
        return
    }
    $operatorName = $operatorToken.Text -replace '^-', ''
    $at = "(position $($operatorToken.Position))"
    $operator = @($Parser.Operators | Where-Object { $_ -eq $operatorName })
    if ($Parser.RefusedOperators.ContainsKey($operatorName.ToLowerInvariant())) {
        $problem = "$($Parser.RefusedOperators[$operatorName.ToLowerInvariant()]) $at"
    } elseif ($operator.Count -eq 0) {
        $known = ($Parser.Operators | ForEach-Object { "-$_" }) -join ', '
        $problem = "unknown operator '$($operatorToken.Text)' $at; the service accepts $known"
    } elseif ($operator[0] -notin $property.Operators) {
        $allowed = ($property.Operators | ForEach-Object { "-$_" }) -join ', '
        $problem = "-$($operator[0]) is not allowed on device.$($property.Name) $at; allowed: $allowed"
    }
    if ($null -ne $problem) {
        Add-IslFilterParseError -Parser $Parser -Message $problem
        return
    }
    $operator = $operator[0]
    $Parser.Pos++

    $value = Read-IslFilterValue -Parser $Parser -Property $property -Operator $operator
    if ($Parser.Error) { return }
    if ($property.Deprecated) {
        $message = ("device.$($property.Name) is deprecated in the filter reference; " +
            'device.operatingSystemVersion compares versions numerically')
        Add-IslFilterWarning -Parser $Parser -Kind 'Deprecated' -Message $message
    }
    if (-not $property.Documented) {
        $message = ("device.$($property.Name) is not in the filter reference; the service accepted it in " +
            'the lab, so it may change without notice')
        Add-IslFilterWarning -Parser $Parser -Kind 'Undocumented' -Message $message
    }
    $end = $Parser.Tokens[$Parser.Pos - 1].End
    $clause = [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.FilterClause'
        Property = $property.Name
        Kind = $property.Kind
        Operator = $operator
        Value = $value
        Text = $Parser.Rule.Substring($token.Position - 1, $end - ($token.Position - 1))
        Position = $token.Position
        Actual = $null
        Matched = $null
    }
    $Parser.Clauses.Add($clause)
    @{ Type = 'Clause'; Clause = $clause }
}
