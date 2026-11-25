function Select-IslRuleCandidate {
    <#
    .SYNOPSIS
    Picks the local candidates for one script rule of a Win32 app.

    .DESCRIPTION
    For Compare-IntuneDeployedScript. When an app has as many script rules of a kind as there are
    local candidates, they pair in name order: rule N takes candidate N. Otherwise the first rule
    takes every candidate, one being a match and more being ambiguous, and the others take none.

    .PARAMETER Candidate
    The local candidates, sorted by name.

    .PARAMETER RuleCount
    How many script rules of the kind the app has.

    .PARAMETER Index
    The rule's position, from 0.

    .EXAMPLE
    Select-IslRuleCandidate -Candidate $files -RuleCount 2 -Index 1

    The second file, when there are two.

    .INPUTS
    None.

    .OUTPUTS
    System.Object. The candidates for the rule.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Candidate = @(),

        [Parameter(Mandatory)]
        [int]$RuleCount,

        [Parameter(Mandatory)]
        [int]$Index
    )

    $candidates = @($Candidate | Where-Object { $_ })
    if ($candidates.Count -eq $RuleCount) {
        $candidates[$Index]
    } elseif ($Index -eq 0) {
        $candidates
    }
}
