function Get-IntuneScriptHealth {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        One line per deployed script policy: findings, drift, assignment and what the devices report.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.HealthReport')]
    param(
        [ValidateSet('Remediation', 'PlatformScript', 'Win32App')]
        [string[]]$Kind = @('Remediation', 'PlatformScript', 'Win32App'),

        [SupportsWildcards()]
        [string[]]$Name = @('*'),

        [string[]]$Id,

        [string]$Path,

        [hashtable]$Map,

        $Settings,

        [switch]$SkipAnalysis,

        [switch]$SkipRunState,

        [switch]$SkipGroupLookup,

        [string]$MarkdownPath
    )
    Write-Verbose "Starting $($MyInvocation.MyCommand.Name) for $($Kind -join ', ')"
    # Captured here: inside the nested functions $PSBoundParameters is their own, not this command's
    $nameGiven = $PSBoundParameters.ContainsKey('Name')

    function Test-Wanted {
        param($Policy)
        $displayName = "$($Policy.displayName)"
        # -Id alone selects by id: -Name's default of '*' only counts when -Name was given or -Id was not
        $byName = ($nameGiven -or -not $Id) -and @($Name | Where-Object { $displayName -like $_ }).Count -gt 0
        $byId = $Id -and "$($Policy.id)" -in $Id
        $byName -or $byId
    }

    function Get-WantedPolicy {
        param([string]$Uri)
        @(Invoke-IslGraphRequest -Uri $Uri -All | Where-Object { Test-Wanted -Policy $_ })
    }

    # The selection parameters every helper command gets
    $selection = @{ Kind = $Kind; Name = $Name }
    if ($Id) { $selection.Id = $Id }

    $findingsByPolicy = @{}
    if (-not $SkipAnalysis) {
        $analysisSplat = $selection.Clone()
        if ($PSBoundParameters.ContainsKey('Settings')) { $analysisSplat.Settings = $Settings }
        if ($SkipGroupLookup) { $analysisSplat.SkipGroupLookup = $true }
        foreach ($finding in @(Test-IntuneDeployedScript @analysisSplat)) {
            $key = "$($finding.PolicyId)"
            if (-not $findingsByPolicy.ContainsKey($key)) {
                $findingsByPolicy[$key] = [System.Collections.Generic.List[object]]::new()
            }
            $findingsByPolicy[$key].Add($finding)
        }
    }

    $driftByPolicy = @{}
    if ($Path) {
        $driftSplat = $selection.Clone()
        $driftSplat.Path = $Path
        if ($Map) { $driftSplat.Map = $Map }
        if ($PSBoundParameters.ContainsKey('Settings')) { $driftSplat.Settings = $Settings }
        foreach ($result in @(Compare-IntuneDeployedScript @driftSplat)) {
            $key = "$($result.PolicyId)"
            if (-not $key) { continue }
            if (-not $driftByPolicy.ContainsKey($key)) {
                $driftByPolicy[$key] = [System.Collections.Generic.List[object]]::new()
            }
            $driftByPolicy[$key].Add($result)
        }
    }

    $appInstall = @{}
    if (-not $SkipRunState -and 'Win32App' -in $Kind) {
        try {
            foreach ($row in @(Get-IslExportReport -ReportName 'AppInstallStatusAggregate')) {
                $appInstall["$($row.ApplicationId)"] = $row
            }
        }
        catch {
            Write-Warning ("The app install export could not be read ($($_.Exception.Message)); the apps' " +
                'device columns stay empty. DeviceManagementManagedDevices.Read.All allows it')
        }
    }

    function Get-RunSummary {
        param([string]$Uri)
        if ($SkipRunState) { return $null }
        try { Invoke-IslGraphRequest -Uri $Uri }
        catch {
            Write-Warning "Run summary could not be read from $Uri ($($_.Exception.Message))"
            $null
        }
    }

    function Get-AssignmentText {
        param($Policy)
        $assignments = @($Policy.assignments | Where-Object { $_ })
        $includes = 0
        $exclusions = 0
        $filters = 0
        $broad = [System.Collections.Generic.List[string]]::new()
        foreach ($assignment in $assignments) {
            $target = $assignment.target
            $type = "$($target.'@odata.type')" -replace '^#microsoft\.graph\.', ''
            if ($type -eq 'exclusionGroupAssignmentTarget') { $exclusions++ }
            else {
                $includes++
                if ($type -eq 'allDevicesAssignmentTarget') { $broad.Add('all devices') }
                if ($type -eq 'allLicensedUsersAssignmentTarget') { $broad.Add('all users') }
            }
            $filterType = "$($target.deviceAndAppManagementAssignmentFilterType)"
            if ($target.deviceAndAppManagementAssignmentFilterId -and $filterType -ne 'none') { $filters++ }
        }
        $text = "$includes include"
        if ($broad.Count) { $text += " ($($broad -join ', '))" }
        if ($exclusions) { $text += ", $exclusions exclusion" }
        if ($filters) { $text += ", $filters filtered" }
        [pscustomobject]@{ Text = $text; Includes = $includes }
    }

    function ConvertTo-Report {
        param(
            [string]$PolicyKind, $Policy, [string]$Context, [int]$Succeeded, [int]$Failed, [int]$Detected,
            [int]$Pending, $LastRun, [string[]]$DeviceNotes, [bool]$HasRunState
        )
        $key = "$($Policy.id)"
        $findings = @(if ($findingsByPolicy.ContainsKey($key)) { $findingsByPolicy[$key] })
        $errors = @($findings | Where-Object Severity -eq 'Error').Count
        $warnings = @($findings | Where-Object Severity -eq 'Warning').Count
        $assignment = Get-AssignmentText -Policy $Policy
        $drift = ''
        $driftDetail = ''
        if ($Path) {
            $results = @(if ($driftByPolicy.ContainsKey($key)) { $driftByPolicy[$key] })
            $states = @($results | ForEach-Object { $_.State })
            $drift = if ($states -contains 'Drifted') { 'Drifted' }
            elseif ($states -contains 'Ambiguous') { 'Ambiguous' }
            elseif ($states -contains 'Missing') { 'Missing' }
            elseif ($states -contains 'NotInTenant') { 'NotInTenant' }
            elseif ($states.Count) { 'InSync' }
            else { 'NoScript' }
            $driftDetail = (@($results | Where-Object State -ne 'InSync' | ForEach-Object {
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
        foreach ($note in $DeviceNotes) { if ($note) { $attention.Add($note) } }
        if ($attention.Count) {
            foreach ($note in $attention) { $notes.Add($note) }
            if ($health -eq 'Healthy') { $health = 'Attention' }
        }

        [pscustomobject]@{
            PSTypeName   = 'IntuneScriptLab.HealthReport'
            Kind         = $PolicyKind
            PolicyName   = "$($Policy.displayName)"
            PolicyId     = $key
            Context      = $Context
            Assigned     = $assignment.Text
            LastModified = $Policy.lastModifiedDateTime
            Errors       = $errors
            Warnings     = $warnings
            Findings     = $findings
            Drift        = $drift
            DriftDetail  = $driftDetail
            Succeeded    = $Succeeded
            Failed       = $Failed
            Detected     = $Detected
            Pending      = $Pending
            LastRun      = $LastRun
            Health       = $health
            Notes        = ($notes -join '; ')
        }
    }

    $reports = [System.Collections.Generic.List[object]]::new()
    if ('Remediation' -in $Kind) {
        $remediations = '/beta/deviceManagement/deviceHealthScripts'
        $fields = 'id,displayName,runAsAccount,lastModifiedDateTime'
        foreach ($summary in (Get-WantedPolicy -Uri "$remediations`?`$select=id,displayName")) {
            $policyUri = "$remediations/$($summary.id)?`$select=$fields&`$expand=assignments"
            $policy = Invoke-IslGraphRequest -Uri $policyUri
            $run = Get-RunSummary -Uri "$remediations/$($summary.id)/runSummary"
            $scriptErrors = [int]$run.detectionScriptErrorDeviceCount + [int]$run.remediationScriptErrorDeviceCount
            $reportSplat = @{
                PolicyKind = 'Remediation'; Policy = $policy; Context = "$($policy.runAsAccount)"
                Succeeded  = [int]$run.noIssueDetectedDeviceCount + [int]$run.issueRemediatedDeviceCount
                Failed     = $scriptErrors
                Detected   = [int]$run.issueDetectedDeviceCount + [int]$run.issueReoccurredDeviceCount
                Pending    = [int]$run.detectionScriptPendingDeviceCount
                LastRun    = $run.lastScriptRunDateTime
                HasRunState = [bool]$run
                DeviceNotes = @(if ([int]$run.detectionScriptNotApplicableDeviceCount) {
                        "$($run.detectionScriptNotApplicableDeviceCount) device(s) not applicable" })
            }
            $reports.Add((ConvertTo-Report @reportSplat))
        }
    }

    if ('PlatformScript' -in $Kind) {
        $scripts = '/beta/deviceManagement/deviceManagementScripts'
        $fields = 'id,displayName,runAsAccount,lastModifiedDateTime'
        foreach ($summary in (Get-WantedPolicy -Uri "$scripts`?`$select=id,displayName")) {
            $policy = Invoke-IslGraphRequest -Uri "$scripts/$($summary.id)?`$select=$fields&`$expand=assignments"
            $run = Get-RunSummary -Uri "$scripts/$($summary.id)/runSummary"
            $reportSplat = @{
                PolicyKind = 'PlatformScript'; Policy = $policy; Context = "$($policy.runAsAccount)"
                Succeeded  = [int]$run.successDeviceCount; Failed = [int]$run.errorDeviceCount
                Detected   = 0; Pending = 0; LastRun = $null; HasRunState = [bool]$run; DeviceNotes = @()
            }
            $reports.Add((ConvertTo-Report @reportSplat))
        }
    }

    if ('Win32App' -in $Kind) {
        $apps = '/beta/deviceAppManagement/mobileApps'
        $listUri = "$apps`?`$filter=isof('microsoft.graph.win32LobApp')&`$select=id,displayName"
        foreach ($summary in (Get-WantedPolicy -Uri $listUri)) {
            # installExperience belongs to the derived type, and $select on the base entity refuses it
            $app = Invoke-IslGraphRequest -Uri "$apps/$($summary.id)?`$expand=assignments"
            $row = $appInstall["$($app.id)"]
            $reportSplat = @{
                PolicyKind = 'Win32App'; Policy = $app; Context = "$($app.installExperience.runAsAccount)"
                Succeeded  = [int]$row.InstalledDeviceCount; Failed = [int]$row.FailedDeviceCount
                Detected   = 0; Pending = [int]$row.PendingInstallDeviceCount; LastRun = $null
                HasRunState = [bool]$row
                DeviceNotes = @(if ([int]$row.NotApplicableDeviceCount) {
                        "$($row.NotApplicableDeviceCount) device(s) not applicable" })
            }
            $reports.Add((ConvertTo-Report @reportSplat))
        }
    }

    if ($MarkdownPath) {
        $rank = @{ Broken = 0; Attention = 1; Healthy = 2 }
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add('# Intune script health')
        $lines.Add('')
        $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        $lines.Add("Generated $stamp by IntuneScriptLab Get-IntuneScriptHealth.")
        $lines.Add('')
        $columns = 'Health', 'PolicyName', 'Context', 'Assigned', 'Errors', 'Warnings', 'Drift', 'Succeeded',
        'Failed', 'Detected', 'Pending', 'LastRun', 'Notes'
        foreach ($group in ($reports | Group-Object Kind | Sort-Object Name)) {
            $lines.Add("## $($group.Name)")
            $lines.Add('')
            $lines.Add('| Health | Policy | Context | Assigned | Errors | Warnings | Drift | Succeeded | ' +
                'Failed | Detected | Pending | Last run | Notes |')
            $lines.Add('|---|---|---|---|---|---|---|---|---|---|---|---|---|')
            foreach ($report in ($group.Group | Sort-Object { $rank[$_.Health] }, PolicyName)) {
                $cells = foreach ($column in $columns) { "$($report.$column)" -replace '\|', '\|' }
                $lines.Add('| ' + ($cells -join ' | ') + ' |')
            }
            $lines.Add('')
        }
        # Resolved against the PowerShell location: .NET's current directory is not $PWD
        $markdownFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($MarkdownPath)
        [System.IO.File]::WriteAllLines($markdownFile, $lines, [System.Text.UTF8Encoding]::new($false))
        Write-Verbose "Markdown report written to $MarkdownPath"
    }

    $reports
    Write-Verbose "Completed $($MyInvocation.MyCommand.Name)"
}
