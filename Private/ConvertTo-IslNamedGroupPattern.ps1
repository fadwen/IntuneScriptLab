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

    $named = [System.Text.StringBuilder]::new()
    $count = 0
    $inClass = $false
    for ($index = 0; $index -lt $Pattern.Length; $index++) {
        $character = $Pattern[$index]
        if ($character -eq '\' -and $index + 1 -lt $Pattern.Length) {
            $null = $named.Append($character).Append($Pattern[$index + 1])
            $index++
            continue
        }
        if ($inClass) {
            if ($character -eq ']') { $inClass = $false }
            $null = $named.Append($character)
            continue
        }
        if ($character -eq '[') { $inClass = $true }
        $opensCapture = $character -eq '(' -and ($index + 1 -ge $Pattern.Length -or $Pattern[$index + 1] -ne '?')
        if ($opensCapture) {
            $count++
            $null = $named.Append("(?<$Prefix$count>")
            continue
        }
        $null = $named.Append($character)
    }
    @{ Pattern = $named.ToString(); Count = $count }
}
