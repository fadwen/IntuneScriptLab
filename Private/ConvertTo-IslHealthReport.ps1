function ConvertTo-IslHealthReport {
    <#
    .SYNOPSIS
    Builds the health line of one deployed script policy.

    .DESCRIPTION
    For Get-IntuneScriptHealth. Puts together the policy's findings from
    Test-IntuneDeployedScript, its drift from Compare-IntuneDeployedScript when the caller
    compared, a summary of its assignments, and the device counts of its run state. The drift is
    the worst state of the policy's scripts: Drifted, Ambiguous, Missing and NotInTenant, in that
    order, then InSync, or NoScript when no local script matched.

    The policy is Broken when it has an error finding, is assigned to nobody, or failed on every
    device that ran it. It needs Attention for a warning finding, devices that failed beside
    devices that succeeded, devices that still detect the issue, drift, no device having
    reported yet, or a note about its devices. Otherwise it is Healthy. Notes lists the reasons.

    .PARAMETER PolicyKind
    Remediation, PlatformScript or Win32App.

    .PARAMETER Policy
    The policy as Graph returns it with $expand=assignments.

    .PARAMETER Context
    The account the policy runs as, such as system or user.

    .PARAMETER FindingsByPolicy
    The findings of Test-IntuneDeployedScript, by policy id. Empty under -SkipAnalysis.

    .PARAMETER DriftByPolicy
    The results of Compare-IntuneDeployedScript, by policy id. Leave it out when the caller did
    not compare, and Drift and DriftDetail stay empty.

    .PARAMETER Succeeded
    The devices that ran the policy without an issue, or that it fixed or installed on.

    .PARAMETER Failed
    The devices on which a script or the install failed.

    .PARAMETER Detected
    The devices whose detection still reports the issue.

    .PARAMETER Pending
    The devices that have not run the policy yet.

    .PARAMETER LastRun
    When a device last ran the policy, as Graph reports it, or nothing.

    .PARAMETER DeviceNotes
    Further notes about the policy's devices, such as how many it does not apply to.

    .PARAMETER HasRunState
    Whether the device counts were read. Without it a count of zero says nothing.

    .EXAMPLE
    ConvertTo-IslHealthReport -PolicyKind 'PlatformScript' -Policy $policy -FindingsByPolicy @{}

    The health line of a platform script without findings or run state: Healthy when it is
    assigned, Broken when it is assigned to nobody.

    .INPUTS
    None.

    .OUTPUTS
    IntuneScriptLab.HealthReport.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.HealthReport')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Remediation', 'PlatformScript', 'Win32App')]
        [string]$PolicyKind,

        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Policy,

        [Parameter()]
        [string]$Context = '',

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [hashtable]$FindingsByPolicy,

        [Parameter()]
        [hashtable]$DriftByPolicy,

        [Parameter()]
        [int]$Succeeded,

        [Parameter()]
        [int]$Failed,

        [Parameter()]
        [int]$Detected,

        [Parameter()]
        [int]$Pending,

        [Parameter()]
        [AllowNull()]
        [object]$LastRun,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$DeviceNotes = @(),

        [Parameter()]
        [switch]$HasRunState
    )

    $key = "$(Get-IslPropertyValue -InputObject $Policy -Name 'id')"
    $findings = @(if ($FindingsByPolicy.ContainsKey($key)) { $FindingsByPolicy[$key] })
    $errors = @($findings | Where-Object Severity -EQ 'Error').Count
    $warnings = @($findings | Where-Object Severity -EQ 'Warning').Count
    $assignment = Get-IslAssignmentSummary -Policy $Policy
    $drift = ''
    $driftDetail = ''
    if ($PSBoundParameters.ContainsKey('DriftByPolicy')) {
        $results = @(if ($DriftByPolicy.ContainsKey($key)) { $DriftByPolicy[$key] })
        $states = @($results | ForEach-Object { $_.State })
        $drift = if ($states -contains 'Drifted') {
            'Drifted'
        } elseif ($states -contains 'Ambiguous') {
            'Ambiguous'
        } elseif ($states -contains 'Missing') {
            'Missing'
        } elseif ($states -contains 'NotInTenant') {
            'NotInTenant'
        } elseif ($states.Count) {
            'InSync'
        } else {
            'NoScript'
        }
        $driftDetail = (@($results | Where-Object State -NE 'InSync' | ForEach-Object {
                    "$($_.Role): $($_.State)$(if ($_.Detail) { " ($($_.Detail))" })"
                })) -join '; '
    }

    $notes = [System.Collections.Generic.List[string]]::new()
    $health = 'Healthy'
    # From the assignments themselves, so -SkipAnalysis does not hide it
    $unassigned = $assignment.Includes -eq 0
    $allFailed = $HasRunState -and $Failed -gt 0 -and $Succeeded -eq 0
    if ($errors) { $notes.Add("$errors error finding(s)") }
    if ($unassigned) { $notes.Add('assigned to nobody') }
    if ($allFailed) { $notes.Add('every device that ran it failed') }
    if ($errors -or $unassigned -or $allFailed) { $health = 'Broken' }
    $attention = [System.Collections.Generic.List[string]]::new()
    if ($warnings) { $attention.Add("$warnings warning finding(s)") }
    if ($HasRunState -and $Failed -gt 0 -and $Succeeded -gt 0) { $attention.Add("$Failed device(s) failed") }
    if ($HasRunState -and $Detected -gt 0) { $attention.Add("$Detected device(s) still detect the issue") }
    if ($drift -in 'Drifted', 'Missing', 'Ambiguous') { $attention.Add("drift: $drift") }
    $reported = $Succeeded + $Failed + $Detected + $Pending
    if ($HasRunState -and $assignment.Includes -gt 0 -and $reported -eq 0 -and -not $unassigned) {
        $attention.Add('no device has reported yet')
    }
    foreach ($note in $DeviceNotes) {
        if ($note) { $attention.Add($note) }
    }
    if ($attention.Count) {
        foreach ($note in $attention) { $notes.Add($note) }
        if ($health -eq 'Healthy') { $health = 'Attention' }
    }

    [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.HealthReport'
        Kind = $PolicyKind
        PolicyName = "$(Get-IslPropertyValue -InputObject $Policy -Name 'displayName')"
        PolicyId = $key
        Context = $Context
        Assigned = $assignment.Text
        LastModified = Get-IslPropertyValue -InputObject $Policy -Name 'lastModifiedDateTime'
        Errors = $errors
        Warnings = $warnings
        Findings = $findings
        Drift = $drift
        DriftDetail = $driftDetail
        Succeeded = $Succeeded
        Failed = $Failed
        Detected = $Detected
        Pending = $Pending
        LastRun = $LastRun
        Health = $health
        Notes = ($notes -join '; ')
    }
}
