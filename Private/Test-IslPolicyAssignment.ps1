function Test-IslPolicyAssignment {
    <#
    .SYNOPSIS
    Checks the assignments of a tenant policy for what the lab saw go wrong.

    .DESCRIPTION
    For Test-IntuneDeployedScript, from validation round 9 ("Assignment sanity" in
    Validation\Findings.md). Three things are reported, each through ConvertTo-IslPolicyFinding,
    so the caller's rule selection and minimum severity apply:

    - No assignment, or exclusions only: no device resolves the policy, so it never runs
      (IslAssignmentIssue, Warning).
    - A remediation's run-once schedule whose time has passed: a device that ran it does not
      again, and one that fetches the policy now runs it once at the fetch (IslScheduleIssue,
      Information). The time is read in UTC or device local time, as the schedule says.
    - A user-context script assigned to all devices or to a group of devices only
      (Test-IslDeviceGroup): it runs as the signed-in user on Entra joined and hybrid joined
      devices and is skipped on Entra registered ones (IslAssignmentIssue, Information).

    .PARAMETER PolicyKind
    Remediation, PlatformScript or Win32App.

    .PARAMETER Policy
    The policy as Graph returns it with $expand=assignments.

    .PARAMETER RunAsAccount
    The account the policy's scripts run as, system or user. A Win32 app passes system: its
    install context is not a script context.

    .PARAMETER GroupState
    The state Test-IslDeviceGroup keeps across the run: Cache and Blocked.

    .PARAMETER SkipGroupLookup
    Reads no group, so no group counts as a device group.

    .PARAMETER IncludeRule
    The caller's -IncludeRule patterns.

    .PARAMETER ExcludeRule
    The caller's -ExcludeRule patterns.

    .PARAMETER MinimumSeverity
    The lowest severity the caller wants, Information by default.

    .EXAMPLE
    Test-IslPolicyAssignment -PolicyKind Remediation -Policy $policy -RunAsAccount system -GroupState $groupState

    A Warning when the remediation has no assignment that includes a target.

    .INPUTS
    None.

    .OUTPUTS
    IntuneScriptLab.DeploymentFinding.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.DeploymentFinding')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Remediation', 'PlatformScript', 'Win32App')]
        [string]$PolicyKind,

        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Policy,

        [Parameter()]
        [AllowNull()]
        [object]$RunAsAccount,

        [Parameter(Mandatory)]
        [hashtable]$GroupState,

        [Parameter()]
        [switch]$SkipGroupLookup,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$IncludeRule,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$ExcludeRule,

        [Parameter()]
        [ValidateSet('Information', 'Warning', 'Error')]
        [string]$MinimumSeverity = 'Information'
    )

    $findingSplat = @{
        PolicyKind = $PolicyKind
        Policy = $Policy
        IncludeRule = $IncludeRule
        ExcludeRule = $ExcludeRule
        MinimumSeverity = $MinimumSeverity
    }
    $assignments = @(Get-IslPropertyValue -InputObject $Policy -Name 'assignments' | Where-Object { $_ })
    $exclusionType = '#microsoft.graph.exclusionGroupAssignmentTarget'
    $includes = @($assignments | Where-Object {
            $target = Get-IslPropertyValue -InputObject $_ -Name 'target'
            "$(Get-IslPropertyValue -InputObject $target -Name '@odata.type')" -ne $exclusionType
        })
    if ($includes.Count -eq 0) {
        $what = if ($assignments.Count -eq 0) { 'No assignment' } else { 'Only exclusion assignments' }
        $noneSplat = @{
            Rule = 'IslAssignmentIssue'
            Severity = 'Warning'
            Message = "${what}: no device resolves the policy, so it never runs anywhere"
            Evidence = 'A remediation with no assignment and one with only an exclusion were absent ' +
            'from every device''s resolved policies after an agent restart, while the same scripts ' +
            'with an include assignment ran (ASSIGN-NONE, ASSIGN-EXCLONLY)'
        }
        ConvertTo-IslPolicyFinding @findingSplat @noneSplat
    }
    foreach ($assignment in $includes) {
        # Only a remediation's assignment has a schedule, and only a run-once one has a date
        $schedule = Get-IslPropertyValue -InputObject $assignment -Name 'runSchedule'
        $scheduleType = "$(Get-IslPropertyValue -InputObject $schedule -Name '@odata.type')"
        if ($scheduleType -ne '#microsoft.graph.deviceHealthScriptRunOnceSchedule') { continue }
        $scheduleDate = Get-IslPropertyValue -InputObject $schedule -Name 'date'
        $scheduleTime = Get-IslPropertyValue -InputObject $schedule -Name 'time'
        $useUtc = [bool](Get-IslPropertyValue -InputObject $schedule -Name 'useUtc')
        $stamp = "$scheduleDate $scheduleTime"
        $at = [datetime]::MinValue
        if (-not [datetime]::TryParse($stamp, [cultureinfo]::InvariantCulture, 'None', [ref]$at)) { continue }
        $now = if ($useUtc) { [datetime]::UtcNow } else { [datetime]::Now }
        if ($at -ge $now) { continue }
        $zone = if ($useUtc) { 'UTC' } else { 'device local time' }
        $when = $at.ToString('yyyy-MM-dd HH:mm:ss')
        $pastSplat = @{
            Rule = 'IslScheduleIssue'
            Severity = 'Information'
            Message = "Run-once schedule at $when ($zone) has passed: a device that already ran it " +
            'will not again, and one that fetches the policy now runs it once at the fetch'
            Evidence = 'A run-once remediation dated two hours earlier ran once about six minutes ' +
            'after a device fetched it, then never again; a device whose clock had not reached ' +
            'the time waited for it (ASSIGN-PAST2, ASSIGN-PAST, REM-RUNONCE)'
        }
        ConvertTo-IslPolicyFinding @findingSplat @pastSplat
    }
    if ("$RunAsAccount" -ne 'user') { return }
    $deviceGroups = foreach ($assignment in $includes) {
        $target = Get-IslPropertyValue -InputObject $assignment -Name 'target'
        $type = "$(Get-IslPropertyValue -InputObject $target -Name '@odata.type')"
        if ($type -eq '#microsoft.graph.allDevicesAssignmentTarget') {
            'all devices'
            continue
        }
        if ($type -ne '#microsoft.graph.groupAssignmentTarget') { continue }
        $groupId = "$(Get-IslPropertyValue -InputObject $target -Name 'groupId')"
        $deviceGroupSplat = @{ GroupId = $groupId; State = $GroupState; SkipGroupLookup = $SkipGroupLookup }
        if (Test-IslDeviceGroup @deviceGroupSplat) { $groupId }
    }
    if ($deviceGroups) {
        $userSplat = @{
            Rule = 'IslAssignmentIssue'
            Severity = 'Information'
            Message = "User context, assigned to devices ($($deviceGroups -join ', ')): runs as the " +
            'signed-in user on Entra joined and hybrid joined devices only; an Entra registered ' +
            'device downloads the policy and skips it'
            Evidence = 'On the Entra registered device the agent logged "This is not AADJ/HAADJ device, ' +
            'skip user context" for every user-context remediation and platform script and never ran ' +
            'them; the joined device ran them as the signed-in user (rounds 1-3, "Join type")'
        }
        ConvertTo-IslPolicyFinding @findingSplat @userSplat
    }
}
