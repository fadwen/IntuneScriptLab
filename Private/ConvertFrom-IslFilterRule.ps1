function ConvertFrom-IslFilterRule {
    <#
    .SYNOPSIS
        Parses an assignment filter rule into its clauses and a tree, refusing what the service refuses.

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
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.FilterRule')]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Rule
    )

    $properties = Get-IslFilterProperty
    $allOperators = @('eq', 'ne', 'in', 'notIn', 'startsWith', 'contains', 'notContains', 'gt', 'ge', 'lt', 'le')
    $refusedOperators = @{
        'not'           = "'not' is not an operator the service accepts; negate with -ne, -notIn or -notContains"
        '!'             = "'!' is not an operator the service accepts; negate with -ne, -notIn or -notContains"
        'endswith'      = '-endsWith is refused by the service; only -startsWith and -contains exist'
        'notendswith'   = '-notEndsWith is refused by the service; only -startsWith and -notContains exist'
        'notstartswith' = '-notStartsWith is refused by the service; only -startsWith exists'
        'equals'        = '-equals is refused by the service; the operator is -eq'
        'notequals'     = '-notEquals is refused by the service; the operator is -ne'
    }
    # Parser state shared by the nested functions: the token cursor and the first failure
    $state = @{ Pos = 0; Error = $null }
    $tokens = [System.Collections.Generic.List[object]]::new()
    $clauses = [System.Collections.Generic.List[object]]::new()
    $warnings = [System.Collections.Generic.List[object]]::new()

    function Write-Failure {
        param([string]$Message)
        if (-not $state.Error) { $state.Error = "Filter rule: $Message" }
    }

    function Get-CurrentToken {
        if ($state.Pos -lt $tokens.Count) { $tokens[$state.Pos] }
    }

    function Test-Connector {
        param([string]$Name)
        $token = Get-CurrentToken
        [bool]($token -and $token.Type -eq 'word' -and ($token.Text -replace '^-', '') -eq $Name)
    }

    function Add-Warning {
        param([string]$Kind, [string]$Message)
        $warnings.Add([pscustomobject]@{
                PSTypeName = 'IntuneScriptLab.FilterWarning'; Kind = $Kind; Message = $Message
            })
    }

    # A double quote inside a value has no escape (FLT-V44, FLT-V45): "say \"hi\"" tokenizes as a
    # string ending in a backslash with a word glued to it, "say ""hi""" as two strings glued
    # together. Either shape where a connector was expected is that mistake, not a missing 'and'
    function Test-EscapedQuote {
        param($Previous, $Next)
        if (-not $Previous -or -not $Next -or $Previous.Type -ne 'string') { return $false }
        $glued = $Next.Position -eq $Previous.End + 1
        [bool]($glued -and ($Next.Type -eq 'string' -or $Previous.Text.EndsWith('\')))
    }

    function Write-EscapeFailure {
        param($Previous)
        Write-Failure ("a double quote inside a value cannot be escaped: the service refuses both \`" and `"`" " +
            "(the value at position $($Previous.Position)); match the parts around the quote with " +
            '-contains or -startsWith instead')
    }

    # The value after an operator: a string, a list, $null or a bare version, checked against
    # what the property and the operator accept
    function Read-Value {
        param($Property, [string]$Operator)
        $token = Get-CurrentToken
        if (-not $token) { Write-Failure "expected a value after -$Operator at the end of the rule"; return }
        $value = $null
        $kind = ''
        $where = "(position $($token.Position))"
        switch ($token.Type) {
            'string' { $value = $token.Text; $kind = 'String'; $state.Pos++ }
            'word' {
                if ($token.Text -in '$null', 'null') { $kind = 'Null' }
                elseif ($token.Text -match '^\d+(\.\d+)*$') { $value = $token.Text; $kind = 'Version' }
                else { Write-Failure "the value $($token.Text) must be in double quotes $where"; return }
                $state.Pos++
            }
            'lbracket' {
                $state.Pos++
                $items = [System.Collections.Generic.List[string]]::new()
                while ($true) {
                    $item = Get-CurrentToken
                    if (-not $item) {
                        Write-Failure "the list opened at position $($token.Position) is not closed"
                        return
                    }
                    if ($item.Type -eq 'rbracket') { $state.Pos++; break }
                    if ($item.Type -ne 'string') {
                        Write-Failure ("a list holds double-quoted strings only; found '$($item.Text)' at " +
                            "position $($item.Position)")
                        return
                    }
                    $items.Add($item.Text)
                    $state.Pos++
                    $next = Get-CurrentToken
                    if ($next -and $next.Type -eq 'comma') { $state.Pos++ }
                    elseif ($next -and $next.Type -ne 'rbracket') {
                        if (Test-EscapedQuote -Previous $item -Next $next) { Write-EscapeFailure -Previous $item }
                        else {
                            Write-Failure ("expected ',' or ']' at position $($next.Position), " +
                                "found '$($next.Text)'")
                        }
                        return
                    }
                }
                if ($items.Count -eq 0) {
                    Write-Failure "the list at position $($token.Position) is empty"
                    return
                }
                $value = $items.ToArray()
                $kind = 'List'
            }
            default { Write-Failure "expected a value after -$Operator $where, found '$($token.Text)'"; return }
        }

        $isList = $Operator -in 'in', 'notIn'
        if ($kind -eq 'List' -and -not $isList) {
            Write-Failure "-$Operator takes a single value; a list needs -in or -notIn $where"
            return
        }
        if ($kind -eq 'Null') {
            if ($Operator -notin 'eq', 'ne') {
                Write-Failure "`$null is accepted with -eq and -ne only $where"
                return
            }
            if ($Property.Kind -eq 'Version') {
                Write-Failure "device.$($Property.Name) cannot be compared with `$null $where"
                return
            }
        }
        if ($Property.Kind -eq 'Version') {
            if ($kind -eq 'List') {
                Write-Failure "device.$($Property.Name) takes a single version, not a list $where"
                return
            }
            if ($kind -in 'String', 'Version' -and "$value".Trim() -notmatch '^\d+(\.\d+){1,3}$') {
                Write-Failure "'$value' is not a version of 2 to 4 numeric parts such as 10.0.22631.3235 $where"
                return
            }
        }
        elseif ($kind -eq 'Version') {
            Write-Failure "the value $value must be in double quotes $where"
            return
        }
        if ($kind -eq 'String' -and $value.Length -eq 0) {
            Write-Failure "an empty string is refused $where; compare with `$null for a device without a value"
            return
        }
        if ($Property.Values -and $Operator -in 'eq', 'in', 'ne', 'notIn') {
            # -eq and -in with such a value match nobody; -ne and -notIn match every device
            $positive = $Operator -in 'eq', 'in'
            foreach ($item in @($value)) {
                if ($null -ne $item -and "$item".Trim() -notin $Property.Values) {
                    $warningKind = if ($positive) { 'NeverMatches' } else { 'AlwaysMatches' }
                    $effect = if ($positive) { 'never matches' } else { 'matches every device' }
                    Add-Warning -Kind $warningKind -Message ("'$item' is not a value a Windows device reports " +
                        "for device.$($Property.Name) ($($Property.Values -join ', ')); the clause at character " +
                        "$($token.Position) $effect")
                }
            }
        }
        if ($Operator -eq 'contains' -and $kind -eq 'String' -and "$value".Trim().Length -eq 0) {
            # The evaluator trims the value to nothing, and every name contains an empty string:
            # -contains " " matched every device (FLT-W27, FLT-Y03)
            Add-Warning -Kind 'AlwaysMatches' -Message ("'$value' is only whitespace, which the evaluator trims " +
                "to nothing, and every value contains that; the clause at character $($token.Position) " +
                'matches every device')
        }
        if ($isList -and $kind -eq 'String') { $value = @($value) }
        $value
    }

    function Read-Clause {
        $token = Get-CurrentToken
        if (-not $token) {
            Write-Failure 'expected a clause such as (device.deviceName -eq "X") at the end'
            return
        }
        $at = "at position $($token.Position)"
        if ($token.Type -ne 'word') {
            Write-Failure "expected a property such as device.deviceName $at, found '$($token.Text)'"
            return
        }
        $bare = ($token.Text -replace '^-', '').ToLowerInvariant()
        if ($bare -in 'and', 'or') { Write-Failure "expected a clause before '$($token.Text)' $at"; return }
        if ($bare -in 'not', '!') { Write-Failure "$($refusedOperators[$bare]) ($at)"; return }
        if ($token.Text -notmatch '^(?<entity>[A-Za-z]+)\.(?<name>[A-Za-z]+)$') {
            Write-Failure "'$($token.Text)' $at is not a property; a clause starts with device.<property>"
            return
        }
        $entity = $Matches.entity
        $name = $Matches.name
        if ($entity -eq 'app') {
            Write-Failure "$($token.Text) $at is a managed app property; a device filter reads device.* properties"
            return
        }
        if ($entity -ne 'device') {
            Write-Failure "unknown entity '$entity' $at; a device filter reads device.* properties"
            return
        }
        $property = $properties[$name.ToLowerInvariant()]
        if (-not $property) {
            $known = ($properties.Values | ForEach-Object { $_.Name } | Sort-Object) -join ', '
            Write-Failure "unknown property device.$name $at. Windows device filters know: $known"
            return
        }
        $state.Pos++

        $operatorToken = Get-CurrentToken
        if (-not $operatorToken -or $operatorToken.Type -ne 'word') {
            $found = if ($operatorToken) { "found '$($operatorToken.Text)'" } else { 'the rule ends' }
            Write-Failure "expected an operator after device.$($property.Name); $found"
            return
        }
        $operatorName = $operatorToken.Text -replace '^-', ''
        $at = "(position $($operatorToken.Position))"
        if ($refusedOperators.ContainsKey($operatorName.ToLowerInvariant())) {
            Write-Failure "$($refusedOperators[$operatorName.ToLowerInvariant()]) $at"
            return
        }
        $operator = @($allOperators | Where-Object { $_ -eq $operatorName })
        if ($operator.Count -eq 0) {
            $known = ($allOperators | ForEach-Object { "-$_" }) -join ', '
            Write-Failure "unknown operator '$($operatorToken.Text)' $at; the service accepts $known"
            return
        }
        $operator = $operator[0]
        if ($operator -notin $property.Operators) {
            $allowed = ($property.Operators | ForEach-Object { "-$_" }) -join ', '
            Write-Failure "-$operator is not allowed on device.$($property.Name) $at; allowed: $allowed"
            return
        }
        $state.Pos++

        $value = Read-Value -Property $property -Operator $operator
        if ($state.Error) { return }
        if ($property.Deprecated) {
            Add-Warning -Kind 'Deprecated' -Message ("device.$($property.Name) is deprecated in the filter " +
                'reference; device.operatingSystemVersion compares versions numerically')
        }
        if (-not $property.Documented) {
            Add-Warning -Kind 'Undocumented' -Message ("device.$($property.Name) is not in the filter " +
                'reference; the service accepted it in the lab, so it may change without notice')
        }
        $end = $tokens[$state.Pos - 1].End
        $clause = [pscustomobject]@{
            PSTypeName = 'IntuneScriptLab.FilterClause'
            Property   = $property.Name
            Kind       = $property.Kind
            Operator   = $operator
            Value      = $value
            Text       = $Rule.Substring($token.Position - 1, $end - ($token.Position - 1))
            Position   = $token.Position
            Actual     = $null
            Matched    = $null
        }
        $clauses.Add($clause)
        @{ Type = 'Clause'; Clause = $clause }
    }

    function Read-Primary {
        $token = Get-CurrentToken
        if (-not $token) { Write-Failure 'expected a clause or "(" at the end of the rule'; return }
        if ($token.Type -eq 'lparen') {
            $state.Pos++
            $inner = Read-Expression
            if ($state.Error) { return }
            $close = Get-CurrentToken
            if (-not $close) { Write-Failure "the '(' at position $($token.Position) is not closed"; return }
            if ($close.Type -ne 'rparen') {
                $previous = $tokens[$state.Pos - 1]
                if (Test-EscapedQuote -Previous $previous -Next $close) { Write-EscapeFailure -Previous $previous }
                else {
                    Write-Failure ("expected 'and', 'or' or ')' at position $($close.Position), " +
                        "found '$($close.Text)'")
                }
                return
            }
            $state.Pos++
            return $inner
        }
        if ($token.Type -eq 'rparen') { Write-Failure "unexpected ')' at position $($token.Position)"; return }
        Read-Clause
    }

    function Read-Conjunction {
        $left = Read-Primary
        if ($state.Error) { return }
        while (Test-Connector -Name 'and') {
            $state.Pos++
            $right = Read-Primary
            if ($state.Error) { return }
            $left = @{ Type = 'And'; Left = $left; Right = $right }
        }
        $left
    }

    function Read-Expression {
        $left = Read-Conjunction
        if ($state.Error) { return }
        while (Test-Connector -Name 'or') {
            $state.Pos++
            $right = Read-Conjunction
            if ($state.Error) { return }
            $left = @{ Type = 'Or'; Left = $left; Right = $right }
        }
        $left
    }

    # Tokens: parentheses, brackets, commas, double-quoted strings (no escapes exist) and words
    $tree = $null
    if ([string]::IsNullOrWhiteSpace($Rule)) { Write-Failure 'the rule is empty' }
    $tokenPattern = '\G(?:(?<ws>\s+)|(?<lparen>\()|(?<rparen>\))|(?<lbracket>\[)|(?<rbracket>\])|' +
        '(?<comma>,)|"(?<string>[^"]*)"|(?<word>[^\s()\[\],"]+))'
    $regex = [regex]::new($tokenPattern)
    $offset = 0
    while (-not $state.Error -and $offset -lt $Rule.Length) {
        $match = $regex.Match($Rule, $offset)
        if (-not $match.Success) {
            Write-Failure "unexpected character '$($Rule[$offset])' at position $($offset + 1)"
            break
        }
        foreach ($kind in 'lparen', 'rparen', 'lbracket', 'rbracket', 'comma', 'string', 'word') {
            if ($match.Groups[$kind].Success) {
                $tokens.Add([pscustomobject]@{
                        Type = $kind; Text = $match.Groups[$kind].Value
                        Position = $match.Index + 1; End = $match.Index + $match.Length
                    })
            }
        }
        $offset = $match.Index + $match.Length
    }

    if (-not $state.Error) {
        $tree = Read-Expression
        $rest = Get-CurrentToken
        if (-not $state.Error -and $rest) {
            $previous = $tokens[$state.Pos - 1]
            if ($rest.Type -eq 'rparen') { Write-Failure "unexpected ')' at position $($rest.Position)" }
            elseif (Test-EscapedQuote -Previous $previous -Next $rest) { Write-EscapeFailure -Previous $previous }
            else { Write-Failure "expected 'and' or 'or' before '$($rest.Text)' at position $($rest.Position)" }
        }
    }

    [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.FilterRule'
        Rule       = $Rule
        Error      = $state.Error
        Tree       = if ($state.Error) { $null } else { $tree }
        Clauses    = if ($state.Error) { @() } else { $clauses.ToArray() }
        Warnings   = if ($state.Error) { @() } else { $warnings.ToArray() }
    }
}
