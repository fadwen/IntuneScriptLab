function Test-IslDeviceGroup {
    <#
    .SYNOPSIS
    Tells whether every member of an Entra group is a device, read once a group.

    .DESCRIPTION
    For Test-IntuneDeployedScript, which notes a user-context script or app assigned to devices.
    Two counts decide it, two Graph calls the first time a group is asked about: every member of
    the group, and the devices among them. A page of members is not enough: a mixed group whose
    first 20 members are devices would pass as a device group. $count needs the eventual
    consistency header and answers with the number as text.

    The answer for each group is kept in the state's Cache. When the members cannot be read, a
    warning names the permission that allows it, the state is marked Blocked, and every group
    after it counts as not a device group without asking again. -SkipGroupLookup makes every
    group count as not a device group and asks nothing.

    .PARAMETER GroupId
    The group's id, from an assignment's target.

    .PARAMETER State
    A hashtable with Cache, a hashtable of answers by group id, and Blocked, which the caller
    creates once for the whole run.

    .PARAMETER SkipGroupLookup
    Reads no group: every group counts as not a device group.

    .EXAMPLE
    Test-IslDeviceGroup -GroupId $groupId -State $groupState

    $true for a group whose members are all devices.

    .INPUTS
    None.

    .OUTPUTS
    System.Boolean.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$GroupId,

        [Parameter(Mandatory)]
        [hashtable]$State,

        [Parameter()]
        [switch]$SkipGroupLookup
    )

    if ($State.Cache.ContainsKey($GroupId)) { return [bool]$State.Cache[$GroupId] }
    $isDeviceGroup = $false
    if (-not $SkipGroupLookup -and -not $State.Blocked) {
        try {
            $countSplat = @{ Headers = @{ ConsistencyLevel = 'eventual' }; ErrorAction = 'Stop' }
            $total = [int](Invoke-IslGraphRequest -Uri "/v1.0/groups/$GroupId/members/`$count" @countSplat)
            $deviceUri = "/v1.0/groups/$GroupId/members/microsoft.graph.device/`$count"
            $devices = [int](Invoke-IslGraphRequest -Uri $deviceUri @countSplat)
            $isDeviceGroup = $total -gt 0 -and $devices -eq $total
        } catch {
            # Without the permission the check is skipped for the rest of the run, not failed
            $State.Blocked = $true
            Write-Warning ("Group members could not be read ($($_.Exception.Message)); the assignment " +
                'check is skipped. GroupMember.Read.All allows it, -SkipGroupLookup silences this')
        }
    }
    $State.Cache[$GroupId] = $isDeviceGroup
    $isDeviceGroup
}
