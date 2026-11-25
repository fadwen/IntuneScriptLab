function Get-IslAssignmentSummary {
    <#
    .SYNOPSIS
    Sums up the assignments of a tenant policy as a short text.

    .DESCRIPTION
    For Get-IntuneScriptHealth. Counts the policy's assignments that include a target and those
    that exclude a group, names an assignment to all devices or all licensed users, and counts the
    assignments that carry an assignment filter. An assignment without a filter carries neither
    filter key, or the filter type none. The text reads like "2 include (all devices), 1
    exclusion, 1 filtered".

    .PARAMETER Policy
    The policy as Graph returns it with $expand=assignments, a dictionary or an object.

    .EXAMPLE
    Get-IslAssignmentSummary -Policy $policy

    Text '1 include (all devices)' and Includes 1 for a policy assigned to all devices.

    .INPUTS
    None.

    .OUTPUTS
    IntuneScriptLab.AssignmentSummary. An object with Text and Includes.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.AssignmentSummary')]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Policy
    )

    $assignments = @(Get-IslPropertyValue -InputObject $Policy -Name 'assignments' | Where-Object { $_ })
    $includes = 0
    $exclusions = 0
    $filters = 0
    $broad = [System.Collections.Generic.List[string]]::new()
    foreach ($assignment in $assignments) {
        $target = Get-IslPropertyValue -InputObject $assignment -Name 'target'
        $targetType = "$(Get-IslPropertyValue -InputObject $target -Name '@odata.type')"
        $type = $targetType -replace '^#microsoft\.graph\.', ''
        if ($type -eq 'exclusionGroupAssignmentTarget') {
            $exclusions++
        } else {
            $includes++
            if ($type -eq 'allDevicesAssignmentTarget') { $broad.Add('all devices') }
            if ($type -eq 'allLicensedUsersAssignmentTarget') { $broad.Add('all users') }
        }
        $filterId = Get-IslPropertyValue -InputObject $target -Name 'deviceAndAppManagementAssignmentFilterId'
        $filterType = Get-IslPropertyValue -InputObject $target -Name 'deviceAndAppManagementAssignmentFilterType'
        if ($filterId -and "$filterType" -ne 'none') { $filters++ }
    }
    $text = "$includes include"
    if ($broad.Count) { $text += " ($($broad -join ', '))" }
    if ($exclusions) { $text += ", $exclusions exclusion" }
    if ($filters) { $text += ", $filters filtered" }
    [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.AssignmentSummary'
        Text = $text
        Includes = $includes
    }
}
