function Get-IslMapEntry {
    <#
    .SYNOPSIS
    Gets the -Map entry of Compare-IntuneDeployedScript for a tenant policy.

    .DESCRIPTION
    A -Map key names a policy by its display name or its id. The first key that matches the
    policy gives its entry, and the key is recorded in Matched, so that the caller can report the
    keys that matched no policy. A policy without a key, or no -Map at all, gives nothing.

    .PARAMETER Policy
    The policy as Graph returns it, with displayName and id.

    .PARAMETER Map
    The caller's -Map. Nothing gives nothing.

    .PARAMETER Matched
    The keys matched so far, which this function adds to.

    .EXAMPLE
    Get-IslMapEntry -Policy $policy -Map @{ 'Detect-Printer' = 'scripts\printer.ps1' } -Matched $mapped

    'scripts\printer.ps1' for the policy named Detect-Printer.

    .INPUTS
    None.

    .OUTPUTS
    System.Object. The entry, a path or a hashtable of paths by role, or nothing.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Policy,

        [Parameter()]
        [AllowNull()]
        [hashtable]$Map,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [hashtable]$Matched
    )

    if (-not $Map) { return }
    $policyName = "$(Get-IslPropertyValue -InputObject $Policy -Name 'displayName')"
    $policyId = "$(Get-IslPropertyValue -InputObject $Policy -Name 'id')"
    foreach ($key in $Map.Keys) {
        if ("$key" -eq $policyName -or "$key" -eq $policyId) {
            $Matched["$key"] = $true
            return $Map[$key]
        }
    }
}
