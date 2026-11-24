function Compare-IslFilterVersion {
    <#
    .SYNOPSIS
    Compares two version texts the way the assignment filter evaluator ordered them.

    .DESCRIPTION
    Both texts are read as four numbers by Get-IslVersionPart and compared part by part, so
    '10.0' equals '10.0.0.0' and '10.0.9' is less than '10.0.10'. When either text is not a
    version there is no order, and the function returns nothing; the filter's gt, ge, lt and le
    then do not match.

    .PARAMETER Actual
    The value the device has.

    .PARAMETER Expected
    The value of the rule.

    .EXAMPLE
    Compare-IslFilterVersion -Actual '10.0.26100' -Expected '10.0.22631'

    Returns 1: the device's version is the greater.

    .INPUTS
    None.

    .OUTPUTS
    System.Int32. -1, 0 or 1, or nothing when a side is not a version.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Actual,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Expected
    )

    $left = @(Get-IslVersionPart -Text $Actual)
    $right = @(Get-IslVersionPart -Text $Expected)
    if ($left.Count -ne 4 -or $right.Count -ne 4) {
        return
    }
    for ($index = 0; $index -lt 4; $index++) {
        if ($left[$index] -lt $right[$index]) { return -1 }
        if ($left[$index] -gt $right[$index]) { return 1 }
    }
    0
}
