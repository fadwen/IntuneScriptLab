#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The health report over a fake tenant: the Graph seam serves the policies with their assignments
    and run summaries, the analysis, the drift and the app install export are mocked, and the
    report's counts, verdicts, notes, switches and Markdown output are checked.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force

    $group = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = 'grp-devices' }
    $allDevices = @{ '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget' }
    $exclusion = @{ '@odata.type' = '#microsoft.graph.exclusionGroupAssignmentTarget'; groupId = 'grp-vip' }
    $filtered = @{
        '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = 'grp-devices'
        deviceAndAppManagementAssignmentFilterId = 'flt-1'; deviceAndAppManagementAssignmentFilterType = 'include'
    }
    $script:Tenant = @{
        remediations    = @(
            @{ id = 'rem-a'; displayName = 'Fix-Widget'; runAsAccount = 'system'
                lastModifiedDateTime = '2026-09-20T10:00:00Z'; assignments = @(@{ target = $filtered }) }
            @{ id = 'rem-b'; displayName = 'Report-Only'; runAsAccount = 'user'
                lastModifiedDateTime = '2026-09-21T10:00:00Z'; assignments = @() }
        )
        runSummaries    = @{
            'rem-a' = @{ noIssueDetectedDeviceCount = 3; issueRemediatedDeviceCount = 1
                detectionScriptErrorDeviceCount = 1; remediationScriptErrorDeviceCount = 0
                issueDetectedDeviceCount = 2; issueReoccurredDeviceCount = 0; detectionScriptPendingDeviceCount = 0
                detectionScriptNotApplicableDeviceCount = 0; lastScriptRunDateTime = '2026-09-28T07:17:04Z' }
            'rem-b' = @{ noIssueDetectedDeviceCount = 0; issueRemediatedDeviceCount = 0
                detectionScriptErrorDeviceCount = 0; remediationScriptErrorDeviceCount = 0
                issueDetectedDeviceCount = 0; issueReoccurredDeviceCount = 0; detectionScriptPendingDeviceCount = 0
                detectionScriptNotApplicableDeviceCount = 0; lastScriptRunDateTime = $null }
            'ps-a'  = @{ successDeviceCount = 5; errorDeviceCount = 0 }
            'ps-b'  = @{ successDeviceCount = 0; errorDeviceCount = 2 }
        }
        platformScripts = @(
            @{ id = 'ps-a'; displayName = 'Set-Wallpaper'; runAsAccount = 'user'
                assignments = @(@{ target = $allDevices }, @{ target = $exclusion }) }
            @{ id = 'ps-b'; displayName = 'Set-Proxy'; runAsAccount = 'system'
                assignments = @(@{ target = $group }) }
        )
        apps            = @(
            @{ id = 'app-a'; displayName = 'Widget 2.0'; installExperience = @{ runAsAccount = 'system' }
                assignments = @(@{ target = $group }) }
            @{ id = 'app-b'; displayName = 'Widget 1.0'; installExperience = @{ runAsAccount = 'user' }
                assignments = @(@{ target = $group }) }
        )
        install         = @(
            [pscustomobject]@{ ApplicationId = 'app-a'; InstalledDeviceCount = '4'; FailedDeviceCount = '0'
                PendingInstallDeviceCount = '1'; NotApplicableDeviceCount = '2' }
        )
    }
    function script:New-Finding {
        param([string]$PolicyId, [string]$Severity, [string]$Rule, [string]$Message)
        [pscustomobject]@{ PolicyId = $PolicyId; Severity = $Severity; RuleName = $Rule; Message = $Message }
    }
    $script:Findings = @(
        New-Finding 'rem-a' 'Warning' 'IslEncodingIssue' 'UTF-8 without a BOM'
        New-Finding 'rem-b' 'Warning' 'IslAssignmentIssue' ('No assignment: no device resolves the policy, ' +
            'so it never runs anywhere')
        New-Finding 'app-b' 'Error' 'IslDetectionRuleIssue' 'Detection rule 1 is a file rule (doesNotExist)'
    )
    $script:Drift = @(
        [pscustomobject]@{ PolicyId = 'rem-a'; Role = 'detection'; State = 'InSync'; Detail = '' }
        [pscustomobject]@{ PolicyId = 'rem-a'; Role = 'remediation'; State = 'Drifted'
            Detail = 'line endings LF locally, CRLF in the tenant' }
        [pscustomobject]@{ PolicyId = 'ps-a'; Role = 'script'; State = 'InSync'; Detail = '' }
    )
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Get-IntuneScriptHealth' -Tag 'Unit', 'Public' {

    BeforeAll {
        # A mock body sees the test file's script scope, so the fake tenant is read from there
        Mock Invoke-IslGraphRequest -ModuleName IntuneScriptLab {
            $tenant = $script:Tenant
            $summary = {
                param($items)
                @($items | ForEach-Object { @{ id = $_.id; displayName = $_.displayName } })
            }
            switch -Regex ($Uri) {
                '^/beta/deviceManagement/deviceHealthScripts\?' { & $summary $tenant.remediations }
                '^/beta/deviceManagement/deviceHealthScripts/([^?/]+)/runSummary' {
                    $tenant.runSummaries[$Matches[1]]
                }
                '^/beta/deviceManagement/deviceHealthScripts/([^?/]+)' {
                    $tenant.remediations | Where-Object id -eq $Matches[1]
                }
                '^/beta/deviceManagement/deviceManagementScripts\?' { & $summary $tenant.platformScripts }
                '^/beta/deviceManagement/deviceManagementScripts/([^?/]+)/runSummary' {
                    $tenant.runSummaries[$Matches[1]]
                }
                '^/beta/deviceManagement/deviceManagementScripts/([^?/]+)' {
                    $tenant.platformScripts | Where-Object id -eq $Matches[1]
                }
                '^/beta/deviceAppManagement/mobileApps\?' { & $summary $tenant.apps }
                '^/beta/deviceAppManagement/mobileApps/([^?/]+)' { $tenant.apps | Where-Object id -eq $Matches[1] }
                default { throw "unexpected uri $Uri" }
            }
        }
        Mock Test-IntuneDeployedScript -ModuleName IntuneScriptLab { $script:Findings }
        Mock Compare-IntuneDeployedScript -ModuleName IntuneScriptLab { $script:Drift }
        Mock Get-IslExportReport -ModuleName IntuneScriptLab { $script:Tenant.install }
    }

    Context 'Core Functionality' {
        BeforeAll {
            $script:Report = @(Get-IntuneScriptHealth -Path $TestDrive)
        }

        It 'reports every policy once with the typed object' {
            $script:Report.Count | Should-Be 6
            $script:Report[0].PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.HealthReport'
            $expected = 'Fix-Widget', 'Report-Only', 'Set-Proxy', 'Set-Wallpaper', 'Widget 1.0', 'Widget 2.0'
            @($script:Report.PolicyName | Sort-Object) | Should-BeCollection $expected
        }

        It 'counts a remediation run summary, its findings and its drift, and asks for attention' {
            $fix = $script:Report | Where-Object PolicyId -eq 'rem-a'
            $fix.Kind | Should-Be 'Remediation'
            $fix.Context | Should-Be 'system'
            $fix.Assigned | Should-Be '1 include, 1 filtered'
            $fix.Succeeded | Should-Be 4
            $fix.Failed | Should-Be 1
            $fix.Detected | Should-Be 2
            $fix.Pending | Should-Be 0
            $fix.LastRun | Should-Be '2026-09-28T07:17:04Z'
            $fix.Warnings | Should-Be 1
            $fix.Errors | Should-Be 0
            @($fix.Findings).Count | Should-Be 1
            $fix.Drift | Should-Be 'Drifted'
            $fix.DriftDetail | Should-Be 'remediation: Drifted (line endings LF locally, CRLF in the tenant)'
            $fix.Health | Should-Be 'Attention'
            $fix.Notes | Should-Be ('1 warning finding(s); 1 device(s) failed; 2 device(s) still detect the ' +
                'issue; drift: Drifted')
        }

        It 'calls a policy assigned to nobody Broken' {
            $report = $script:Report | Where-Object PolicyId -eq 'rem-b'
            $report.Assigned | Should-Be '0 include'
            $report.Health | Should-Be 'Broken'
            $report.Notes | Should-BeLikeString 'assigned to nobody*'
            $report.Drift | Should-Be 'NoScript'
        }

        It 'calls a policy with an error finding Broken, and one whose every run failed' {
            ($script:Report | Where-Object PolicyId -eq 'app-b').Health | Should-Be 'Broken'
            ($script:Report | Where-Object PolicyId -eq 'app-b').Notes | Should-BeLikeString '1 error finding(s)*'
            $proxy = $script:Report | Where-Object PolicyId -eq 'ps-b'
            $proxy.Health | Should-Be 'Broken'
            $proxy.Notes | Should-Be 'every device that ran it failed'
        }

        It 'calls a clean platform script Healthy and describes broad and excluded assignments' {
            $wallpaper = $script:Report | Where-Object PolicyId -eq 'ps-a'
            $wallpaper.Health | Should-Be 'Healthy'
            $wallpaper.Assigned | Should-Be '1 include (all devices), 1 exclusion'
            $wallpaper.Succeeded | Should-Be 5
            $wallpaper.Drift | Should-Be 'InSync'
            $wallpaper.Notes | Should-Be ''
        }

        It 'reads app install counts from the aggregate export and notes not-applicable devices' {
            $widget = $script:Report | Where-Object PolicyId -eq 'app-a'
            $widget.Context | Should-Be 'system'
            $widget.Succeeded | Should-Be 4
            $widget.Pending | Should-Be 1
            $widget.Health | Should-Be 'Attention'
            $widget.Notes | Should-Be '2 device(s) not applicable'
            Should-Invoke Get-IslExportReport -ModuleName IntuneScriptLab -ParameterFilter {
                $ReportName -eq 'AppInstallStatusAggregate'
            } -Times 1 -Exactly -Scope Context
        }
    }

    Context 'Switches' {
        It 'leaves the device columns and the export alone with -SkipRunState' {
            $report = @(Get-IntuneScriptHealth -SkipRunState)
            ($report | Where-Object PolicyId -eq 'rem-a').Succeeded | Should-Be 0
            ($report | Where-Object PolicyId -eq 'ps-b').Health | Should-Be 'Healthy'
            ($report | Where-Object PolicyId -eq 'rem-a').Drift | Should-Be ''
            Should-Invoke Invoke-IslGraphRequest -ModuleName IntuneScriptLab -ParameterFilter {
                $Uri -like '*/runSummary'
            } -Times 0 -Exactly
            Should-Invoke Get-IslExportReport -ModuleName IntuneScriptLab -Times 0 -Exactly
        }

        It 'leaves the findings alone with -SkipAnalysis' {
            $report = @(Get-IntuneScriptHealth -SkipAnalysis -SkipRunState)
            ($report | Where-Object PolicyId -eq 'rem-b').Health | Should-Be 'Healthy'
            ($report | Where-Object PolicyId -eq 'app-b').Errors | Should-Be 0
            Should-Invoke Test-IntuneDeployedScript -ModuleName IntuneScriptLab -Times 0 -Exactly
        }

        It 'reads only the kinds asked for and flags an assigned policy nobody reported on' {
            $report = @(Get-IntuneScriptHealth -Kind Win32App -SkipAnalysis)
            $report.Kind | Should-All { $_ -eq 'Win32App' }
            ($report | Where-Object PolicyId -eq 'app-b').Health | Should-Be 'Healthy'
            Should-Invoke Invoke-IslGraphRequest -ModuleName IntuneScriptLab -ParameterFilter {
                $Uri -like '*deviceHealthScripts*'
            } -Times 0 -Exactly
        }

        It 'warns and carries on when the app install export fails' {
            Mock Get-IslExportReport -ModuleName IntuneScriptLab { throw 'Forbidden' }
            $warnings = @()
            $report = @(Get-IntuneScriptHealth -Kind Win32App -SkipAnalysis -WarningVariable warnings 3>$null)
            $report.Count | Should-Be 2
            "$($warnings[0])" | Should-BeLikeString '*app install export could not be read*'
        }

        It 'writes the Markdown report, Broken first within each kind' {
            $file = Join-Path $TestDrive 'health.md'
            $null = Get-IntuneScriptHealth -MarkdownPath $file
            $text = Get-Content -Path $file -Raw
            # Group-Object orders the kinds by name
            $text | Should-BeLikeString '# Intune script health*## PlatformScript*## Remediation*## Win32App*'
            $lines = @(Get-Content -Path $file | Where-Object { $_ -like '| *' -and $_ -notlike '| Health *' })
            $remediationRows = @($lines | Where-Object { $_ -like '*Fix-Widget*' -or $_ -like '*Report-Only*' })
            $remediationRows[0] | Should-BeLikeString '| Broken | Report-Only | user | 0 include | 0 | 1 |*'
            $remediationRows[1] | Should-BeLikeString '| Attention | Fix-Widget | system |*'
        }
    }
}
