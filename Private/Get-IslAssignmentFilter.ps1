function Get-IslAssignmentFilter {
    <#
    .SYNOPSIS
    Gets an assignment filter from the tenant, asking Graph once for each filter.

    .DESCRIPTION
    For Test-IntuneDeployedScript, which checks the filters on a policy's assignments. The filter
    for each id is kept in the state's Cache. When the filters cannot be read, a warning names
    the permission that allows it, the state is marked Blocked, and every filter after it gives
    nothing without asking again.

    .PARAMETER FilterId
    The filter's id, from an assignment's target.

    .PARAMETER State
    A hashtable with Cache, a hashtable of filters by id, and Blocked, which the caller creates
    once for the whole run.

    .EXAMPLE
    Get-IslAssignmentFilter -FilterId $filterId -State $filterState

    The filter with its displayName and rule.

    .INPUTS
    None.

    .OUTPUTS
    System.Object. The filter as Graph returns it, or nothing.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [string]$FilterId,

        [Parameter(Mandatory)]
        [hashtable]$State
    )

    if ($State.Cache.ContainsKey($FilterId)) {
        $filter = $State.Cache[$FilterId]
    } else {
        $filter = $null
        if (-not $State.Blocked) {
            try {
                $filterUri = "/beta/deviceManagement/assignmentFilters/$FilterId"
                $filter = Invoke-IslGraphRequest -Uri $filterUri -ErrorAction Stop
            } catch {
                # Without the permission the check is skipped for the rest of the run, not failed
                $State.Blocked = $true
                Write-Warning ("Assignment filters could not be read ($($_.Exception.Message)); the filter " +
                    'check is skipped. DeviceManagementConfiguration.Read.All allows it')
            }
        }
        $State.Cache[$FilterId] = $filter
    }
    if ($null -ne $filter) { $filter }
}
