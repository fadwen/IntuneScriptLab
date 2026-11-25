function New-IslFilterParser {
    <#
    .SYNOPSIS
    Reads an assignment filter rule into tokens and the state its parser works on.

    .DESCRIPTION
    For ConvertFrom-IslFilterRule. The rule is split into parentheses, brackets, commas,
    double-quoted strings, which have no escapes, and words. The state that the Read-IslFilter*
    functions share is returned with the tokens: the cursor (Pos), the first failure (Error), the
    clauses and warnings read so far, the rule itself, the Windows device properties from
    Get-IslFilterProperty, the operators the service accepts and the reasons it refuses others.

    An empty rule, or a character that no token can start with, sets Error, and tokenizing stops
    at that character.

    .PARAMETER Rule
    The filter rule text, such as (device.deviceName -eq "LAB-PC-01").

    .EXAMPLE
    $parser = New-IslFilterParser -Rule '(device.deviceName -eq "X")'

    $parser.Tokens holds the five tokens of the rule, and $parser.Pos is 0.

    .INPUTS
    None.

    .OUTPUTS
    System.Collections.Hashtable. The parser state, with the keys Rule, Pos, Error, Tokens,
    Clauses, Warnings, Properties, Operators and RefusedOperators.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Builds an object in memory and changes nothing outside it.')]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Rule
    )

    $parser = @{
        Rule = $Rule
        Pos = 0
        Error = $null
        Tokens = [System.Collections.Generic.List[object]]::new()
        Clauses = [System.Collections.Generic.List[object]]::new()
        Warnings = [System.Collections.Generic.List[object]]::new()
        Properties = Get-IslFilterProperty
        Operators = @('eq', 'ne', 'in', 'notIn', 'startsWith', 'contains', 'notContains', 'gt', 'ge', 'lt', 'le')
        RefusedOperators = @{
            'not' = "'not' is not an operator the service accepts; negate with -ne, -notIn or -notContains"
            '!' = "'!' is not an operator the service accepts; negate with -ne, -notIn or -notContains"
            'endswith' = '-endsWith is refused by the service; only -startsWith and -contains exist'
            'notendswith' = '-notEndsWith is refused by the service; only -startsWith and -notContains exist'
            'notstartswith' = '-notStartsWith is refused by the service; only -startsWith exists'
            'equals' = '-equals is refused by the service; the operator is -eq'
            'notequals' = '-notEquals is refused by the service; the operator is -ne'
        }
    }

    if ([string]::IsNullOrWhiteSpace($Rule)) {
        Add-IslFilterParseError -Parser $parser -Message 'the rule is empty'
    }
    $tokenPattern = '\G(?:(?<ws>\s+)|(?<lparen>\()|(?<rparen>\))|(?<lbracket>\[)|(?<rbracket>\])|' +
        '(?<comma>,)|"(?<string>[^"]*)"|(?<word>[^\s()\[\],"]+))'
    $regex = [regex]::new($tokenPattern)
    $offset = 0
    while (-not $parser.Error -and $offset -lt $Rule.Length) {
        $match = $regex.Match($Rule, $offset)
        if (-not $match.Success) {
            Add-IslFilterParseError -Parser $parser -Message (
                "unexpected character '$($Rule[$offset])' at position $($offset + 1)")
            break
        }
        foreach ($kind in 'lparen', 'rparen', 'lbracket', 'rbracket', 'comma', 'string', 'word') {
            if ($match.Groups[$kind].Success) {
                $parser.Tokens.Add([pscustomobject]@{
                        Type = $kind; Text = $match.Groups[$kind].Value
                        Position = $match.Index + 1; End = $match.Index + $match.Length
                    })
            }
        }
        $offset = $match.Index + $match.Length
    }
    $parser
}
