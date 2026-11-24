function Test-IslRuleSelected {
    <#
    .SYNOPSIS
    Tells whether a rule name passes an include list and an exclude list of wildcard patterns.

    .DESCRIPTION
    The rule filter of Test-IntuneScript, for -IncludeRule, -ExcludeRule and the same keys of a
    settings file. A rule is selected when the include list is empty or one of its patterns
    matches the name, and no pattern of the exclude list matches it. The patterns are those of
    the -like operator, so the comparison ignores letter case.

    .PARAMETER RuleName
    The name of the rule without its Find- prefix, such as IslExitCodeIssue.

    .PARAMETER Include
    Patterns of the rules to run. Empty or left out, every rule is included.

    .PARAMETER Exclude
    Patterns of the rules to skip. An exclusion wins over an inclusion.

    .EXAMPLE
    Test-IslRuleSelected -RuleName 'IslLongSleep' -Include 'IslLong*' -Exclude 'IslLongSleep'

    Returns $false: the rule is included by its pattern and then excluded by name.

    .INPUTS
    None.

    .OUTPUTS
    System.Boolean.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$RuleName,

        [Parameter()]
        [AllowEmptyCollection()]
        [AllowNull()]
        [string[]]$Include,

        [Parameter()]
        [AllowEmptyCollection()]
        [AllowNull()]
        [string[]]$Exclude
    )

    $included = @($Include | Where-Object { $_ })
    $excluded = @($Exclude | Where-Object { $_ })
    if ($included.Count -gt 0 -and @($included | Where-Object { $RuleName -like $_ }).Count -eq 0) {
        return $false
    }
    if (@($excluded | Where-Object { $RuleName -like $_ }).Count -gt 0) {
        return $false
    }
    $true
}
