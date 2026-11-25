function Test-IslPolicySelected {
    <#
    .SYNOPSIS
    Tells whether a tenant policy is one that the caller's -Name and -Id select.

    .DESCRIPTION
    For the tenant commands Test-IntuneDeployedScript, Compare-IntuneDeployedScript and
    Get-IntuneScriptHealth, which select policies the same way. A policy is selected when its
    displayName matches one of the -Name wildcard patterns, or when its id is one of -Id. -Name
    has a default of '*', which would select every policy, so it counts only when the caller gave
    -Name or did not give -Id: -Id alone selects by id.

    .PARAMETER Policy
    The policy as Graph returns it, a dictionary or an object with displayName and id.

    .PARAMETER Name
    The wildcard patterns of the caller's -Name.

    .PARAMETER Id
    The ids of the caller's -Id. Nothing when the caller gave none.

    .PARAMETER NameGiven
    Whether the caller gave -Name itself, rather than taking its default.

    .EXAMPLE
    Test-IslPolicySelected -Policy $policy -Name 'Detect-*' -NameGiven

    $true for a policy named Detect-Printer.

    .INPUTS
    None.

    .OUTPUTS
    System.Boolean.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Policy,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$Name = @('*'),

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$Id,

        [Parameter()]
        [switch]$NameGiven
    )

    $displayName = "$(Get-IslPropertyValue -InputObject $Policy -Name 'displayName')"
    $policyId = "$(Get-IslPropertyValue -InputObject $Policy -Name 'id')"
    $byName = ($NameGiven -or -not $Id) -and @($Name | Where-Object { $displayName -like $_ }).Count -gt 0
    $byId = [bool]$Id -and $policyId -in $Id
    [bool]($byName -or $byId)
}
