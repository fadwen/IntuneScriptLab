function ConvertTo-IslNamedGroupPattern {
    <#
    .SYNOPSIS
    Renames the capturing groups of a regular expression so that several fit into one pattern.

    .DESCRIPTION
    The agent-log reader joins every event pattern into one alternation and must still tell
    which pattern matched and read its own captures. Each capturing group becomes a named group,
    the prefix followed by its number from 1. A group that does not capture, such as (?:...) or
    (?<name>...), is left as it is, and so is a parenthesis that is escaped or inside a character
    class.

    In the joined pattern every group has a name, and .NET numbers groups across the whole
    expression, so a numbered backreference such as \1 would refer to a group of another
    pattern. A backreference \n or \k<n> outside a character class, whose n is one of the
    pattern's own groups, is therefore written as \k<prefix n>. A larger number is left as it
    is, as .NET reads it on its own, and so is a conditional that names a group by number, such
    as (?(1)...), which no event pattern uses.

    .PARAMETER Pattern
    The regular expression.

    .PARAMETER Prefix
    The start of the new group names, such as e3g.

    .EXAMPLE
    ConvertTo-IslNamedGroupPattern -Pattern '^exit code is (-?\d+)' -Prefix 'e3g'

    Returns @{ Pattern = '^exit code is (?<e3g1>-?\d+)'; Count = 1 }.

    .INPUTS
    None.

    .OUTPUTS
    System.Collections.Hashtable. Pattern, the renamed expression, and Count, the number of
    groups that were renamed.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Pattern,

        [Parameter(Mandatory)]
        [string]$Prefix
    )

    # A backreference can come before the last group, so the text is kept in pieces and a
    # backreference is resolved once the number of groups is known
    $pieces = [System.Collections.Generic.List[object]]::new()
    $text = [System.Text.StringBuilder]::new()
    $backreference = [regex]::new('\G\\(?:([1-9][0-9]*)|k<([1-9][0-9]*)>)')
    $count = 0
    $inClass = $false
    for ($index = 0; $index -lt $Pattern.Length; $index++) {
        $character = $Pattern[$index]
        if ($character -eq '\' -and $index + 1 -lt $Pattern.Length) {
            $reference = $null
            if (-not $inClass) { $reference = $backreference.Match($Pattern, $index) }
            if ($null -ne $reference -and $reference.Success) {
                $pieces.Add($text.ToString())
                $null = $text.Clear()
                $digits = $reference.Groups[2].Value
                if ($reference.Groups[1].Success) { $digits = $reference.Groups[1].Value }
                # More digits than nine is more groups than any pattern has
                $number = [int]::MaxValue
                if ($digits.Length -le 9) { $number = [int]$digits }
                $pieces.Add(@{ Number = $number; Text = $reference.Value })
                $index += $reference.Length - 1
                continue
            }
            $null = $text.Append($character).Append($Pattern[$index + 1])
            $index++
            continue
        }
        if ($inClass) {
            if ($character -eq ']') { $inClass = $false }
            $null = $text.Append($character)
            continue
        }
        if ($character -eq '[') { $inClass = $true }
        $opensCapture = $character -eq '(' -and ($index + 1 -ge $Pattern.Length -or $Pattern[$index + 1] -ne '?')
        if ($opensCapture) {
            $count++
            $null = $text.Append("(?<$Prefix$count>")
            continue
        }
        $null = $text.Append($character)
    }
    $pieces.Add($text.ToString())

    $named = [System.Text.StringBuilder]::new()
    foreach ($piece in $pieces) {
        if ($piece -is [string]) {
            $null = $named.Append($piece)
        } elseif ($piece['Number'] -le $count) {
            $null = $named.Append("\k<$Prefix$($piece['Number'])>")
        } else {
            $null = $named.Append($piece['Text'])
        }
    }
    @{ Pattern = $named.ToString(); Count = $count }
}
