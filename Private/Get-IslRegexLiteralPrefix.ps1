function Get-IslRegexLiteralPrefix {
    <#
    .SYNOPSIS
    Gets the literal text a regular expression starts with.

    .DESCRIPTION
    A message that the pattern matches must contain this text, and looking for it is cheaper
    than running the pattern; most lines of the agent's logs match no pattern at all. The text is
    read up to the first metacharacter. A leading ^ is skipped, an escaped punctuation character
    counts as itself, and an escaped letter or digit ends the text, because it stands for a
    class. When a quantifier follows the text, its last character is optional in the pattern and
    is left out. A pattern with a | outside every group and character class, such as
    'Script failed|Script timed out', has alternatives that need not share any text, and gives
    an empty string.

    .PARAMETER Pattern
    The regular expression.

    .EXAMPLE
    Get-IslRegexLiteralPrefix -Pattern '^Powershell exit code is (-?\d+)'

    Returns 'Powershell exit code is '.

    .INPUTS
    None.

    .OUTPUTS
    System.String. The literal text, or an empty string when the pattern starts with a
    metacharacter or has alternatives at its top level.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Pattern
    )

    $depth = 0
    $inClass = $false
    for ($index = 0; $index -lt $Pattern.Length; $index++) {
        $character = $Pattern[$index]
        if ($character -eq '\') {
            $index++
        } elseif ($inClass) {
            if ($character -eq ']') { $inClass = $false }
        } elseif ($character -eq '[') {
            $inClass = $true
        } elseif ($character -eq '(') {
            $depth++
        } elseif ($character -eq ')') {
            if ($depth -gt 0) { $depth-- }
        } elseif ($character -eq '|' -and $depth -eq 0) {
            return ''
        }
    }

    $literal = [System.Text.StringBuilder]::new()
    $index = if ($Pattern.StartsWith('^')) { 1 } else { 0 }
    while ($index -lt $Pattern.Length) {
        $character = $Pattern[$index]
        if ($character -eq '\') {
            if ($index + 1 -ge $Pattern.Length) { break }
            $next = $Pattern[$index + 1]
            if ([char]::IsLetterOrDigit($next)) { break }
            $null = $literal.Append($next)
            $index += 2
            continue
        }
        if ('()[]{}.*+?|^$'.IndexOf($character) -ge 0) { break }
        $null = $literal.Append($character)
        $index++
    }
    if ($index -lt $Pattern.Length -and '*?{'.IndexOf($Pattern[$index]) -ge 0 -and $literal.Length) {
        $literal.Length--
    }
    $literal.ToString()
}
