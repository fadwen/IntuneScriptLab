function Get-IntuneScriptHealth {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        One line per deployed script policy: findings, drift, assignment and what the devices report.
    #>
    [CmdletBinding(SupportsShouldProcess)]
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
    # Which policies of each list to read; -Id alone selects by id, so whether -Name was given counts
    $wanted = @{ Name = $Name; Id = $Id; NameGiven = $PSBoundParameters.ContainsKey('Name') }

    # The selection parameters every helper command gets
    $selection = @{ Kind = $Kind; Name = $Name }
    if ($Id) { $selection.Id = $Id }

    # The analysis and the drift comparison each read the tenant; a read that fails ends this
    # command as it ends them
    try {
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
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # The install counts come from an export job, and creating one is a write to the tenant:
    # -WhatIf leaves it out, and the apps' device columns stay empty
    $appInstall = @{}
    $wantsExport = -not $SkipRunState -and 'Win32App' -in $Kind
    $exportAction = 'Create a report export job for the app install counts'
    if ($wantsExport -and $PSCmdlet.ShouldProcess('Microsoft Graph', $exportAction)) {
        try {
            foreach ($row in @(Get-IslExportReport -ReportName 'AppInstallStatusAggregate')) {
                $appInstall["$(Get-IslPropertyValue -InputObject $row -Name 'ApplicationId')"] = $row
            }
        }
        catch {
            Write-Warning ("The app install export could not be read ($($_.Exception.Message)); the apps' " +
                'device columns stay empty. Creating an export job needs a ReadWrite scope: ' +
                'DeviceManagementApps.ReadWrite.All, DeviceManagementConfiguration.ReadWrite.All or ' +
                'DeviceManagementManagedDevices.ReadWrite.All')
        }
    }

    # What every health line is built from besides its own policy; the drift only when compared
    $reportBase = @{ FindingsByPolicy = $findingsByPolicy }
    if ($Path) { $reportBase.DriftByPolicy = $driftByPolicy }
    # A policy that cannot be read ends the command: a report with gaps would read as health
    try {
        $reports = [System.Collections.Generic.List[object]]::new()
        if ('Remediation' -in $Kind) {
            $remediations = '/beta/deviceManagement/deviceHealthScripts'
            $fields = 'id,displayName,runAsAccount,lastModifiedDateTime'
            foreach ($summary in (Get-IslSelectedPolicy -Uri "$remediations`?`$select=id,displayName" @wanted)) {
                $summaryId = Get-IslPropertyValue -InputObject $summary -Name 'id'
                $policyUri = "$remediations/$summaryId`?`$select=$fields&`$expand=assignments"
                $policy = Invoke-IslGraphRequest -Uri $policyUri
                $run = $null
                if (-not $SkipRunState) { $run = Get-IslRunSummary -Uri "$remediations/$summaryId/runSummary" }
                # The summary is absent under -SkipRunState and when it could not be read, and a
                # counter that is not in it counts as zero
                $runCount = @{}
                $counters = @(
                    'noIssueDetected'
                    'issueRemediated'
                    'issueDetected'
                    'issueReoccurred'
                    'detectionScriptError'
                    'remediationScriptError'
                    'detectionScriptPending'
                    'detectionScriptNotApplicable'
                )
                foreach ($counter in $counters) {
                    $counterValue = Get-IslPropertyValue -InputObject $run -Name "${counter}DeviceCount"
                    $runCount[$counter] = [int]$counterValue
                }
                $notApplicable = $runCount['detectionScriptNotApplicable']
                $reportSplat = @{
                    PolicyKind = 'Remediation'
                    Policy = $policy
                    Context = "$(Get-IslPropertyValue -InputObject $policy -Name 'runAsAccount')"
                    Succeeded = $runCount['noIssueDetected'] + $runCount['issueRemediated']
                    Failed = $runCount['detectionScriptError'] + $runCount['remediationScriptError']
                    Detected = $runCount['issueDetected'] + $runCount['issueReoccurred']
                    Pending = $runCount['detectionScriptPending']
                    LastRun = Get-IslPropertyValue -InputObject $run -Name 'lastScriptRunDateTime'
                    HasRunState = [bool]$run
                    DeviceNotes = @(if ($notApplicable) { "$notApplicable device(s) not applicable" })
                }
                $reports.Add((ConvertTo-IslHealthReport @reportSplat @reportBase))
            }
        }

        if ('PlatformScript' -in $Kind) {
            $scripts = '/beta/deviceManagement/deviceManagementScripts'
            $fields = 'id,displayName,runAsAccount,lastModifiedDateTime'
            foreach ($summary in (Get-IslSelectedPolicy -Uri "$scripts`?`$select=id,displayName" @wanted)) {
                $summaryId = Get-IslPropertyValue -InputObject $summary -Name 'id'
                $policy = Invoke-IslGraphRequest -Uri "$scripts/$summaryId`?`$select=$fields&`$expand=assignments"
                $run = $null
                if (-not $SkipRunState) { $run = Get-IslRunSummary -Uri "$scripts/$summaryId/runSummary" }
                $reportSplat = @{
                    PolicyKind = 'PlatformScript'
                    Policy = $policy
                    Context = "$(Get-IslPropertyValue -InputObject $policy -Name 'runAsAccount')"
                    Succeeded = [int](Get-IslPropertyValue -InputObject $run -Name 'successDeviceCount')
                    Failed = [int](Get-IslPropertyValue -InputObject $run -Name 'errorDeviceCount')
                    Detected = 0
                    Pending = 0
                    LastRun = $null
                    HasRunState = [bool]$run
                    DeviceNotes = @()
                }
                $reports.Add((ConvertTo-IslHealthReport @reportSplat @reportBase))
            }
        }

        if ('Win32App' -in $Kind) {
            $apps = '/beta/deviceAppManagement/mobileApps'
            $listUri = "$apps`?`$filter=isof('microsoft.graph.win32LobApp')&`$select=id,displayName"
            foreach ($summary in (Get-IslSelectedPolicy -Uri $listUri @wanted)) {
                # installExperience belongs to the derived type, and $select on the base entity refuses it
                $summaryId = Get-IslPropertyValue -InputObject $summary -Name 'id'
                $app = Invoke-IslGraphRequest -Uri "$apps/$summaryId`?`$expand=assignments"
                # An app that no device has reported on has no row in the export
                $row = $appInstall["$(Get-IslPropertyValue -InputObject $app -Name 'id')"]
                $installExperience = Get-IslPropertyValue -InputObject $app -Name 'installExperience'
                $notApplicable = [int](Get-IslPropertyValue -InputObject $row -Name 'NotApplicableDeviceCount')
                $reportSplat = @{
                    PolicyKind = 'Win32App'
                    Policy = $app
                    Context = "$(Get-IslPropertyValue -InputObject $installExperience -Name 'runAsAccount')"
                    Succeeded = [int](Get-IslPropertyValue -InputObject $row -Name 'InstalledDeviceCount')
                    Failed = [int](Get-IslPropertyValue -InputObject $row -Name 'FailedDeviceCount')
                    Detected = 0
                    Pending = [int](Get-IslPropertyValue -InputObject $row -Name 'PendingInstallDeviceCount')
                    LastRun = $null
                    HasRunState = [bool]$row
                    DeviceNotes = @(if ($notApplicable) { "$notApplicable device(s) not applicable" })
                }
                $reports.Add((ConvertTo-IslHealthReport @reportSplat @reportBase))
            }
        }
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # The reports are read from the tenant and are returned in any case. The file is the one
    # thing this command writes, and -WhatIf leaves it unwritten
    $markdownFile = $null
    if ($MarkdownPath) {
        # Resolved against the PowerShell location: .NET's current directory is not $PWD
        $markdownFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($MarkdownPath)
    }
    if ($markdownFile -and $PSCmdlet.ShouldProcess($markdownFile, 'Write the Markdown report')) {
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
        try {
            [System.IO.File]::WriteAllLines($markdownFile, $lines, [System.Text.UTF8Encoding]::new($false))
            Write-Verbose "Markdown report written to $MarkdownPath"
        } catch {
            # The reports were read and are returned below. A file that could not be written is
            # reported, and the caller decides with -ErrorAction whether that ends the command
            $PSCmdlet.WriteError($_)
        }
    }

    $reports
    Write-Verbose "Completed $($MyInvocation.MyCommand.Name)"
}
