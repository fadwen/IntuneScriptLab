#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The health report over a fake tenant: the Graph seam serves the policies with their assignments
    and run summaries, the analysis, the drift and the app install export are mocked, and the
    report's counts, verdicts, notes, switches and Markdown output are checked.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
    # Stands in for the Graph module in a calling script: every request fails
    $script:GraphDown = 'function global:Invoke-MgGraphRequest { ' +
        "throw [System.InvalidOperationException]::new('Graph is down') }"

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
        <#
        .SYNOPSIS
            Creates a finding of the pre-flight for one policy of the fake tenant.

        .DESCRIPTION
            Gives an object with the members of a pre-flight finding that the health report reads,
            so that the mocked pre-flight can return findings for chosen policies.

        .PARAMETER PolicyId
            The id of the policy the finding is about.

        .PARAMETER Severity
            The severity of the finding, such as Warning or Error.

        .PARAMETER Rule
            The name of the rule that reported the finding.

        .PARAMETER Message
            The message of the finding.

        .EXAMPLE
            New-Finding 'rem-a' 'Warning' 'IslEncodingIssue' 'UTF-8 without a BOM'

            Creates a warning about the encoding of the policy rem-a.

        .INPUTS
            None.

        .OUTPUTS
            IntuneScriptLab.Test.Finding. PolicyId, Severity, RuleName and Message.
        #>
        [CmdletBinding()]
        [OutputType('IntuneScriptLab.Test.Finding')]
        param(
            [string]$PolicyId,

            [string]$Severity,

            [string]$Rule,

            [string]$Message
        )

        [pscustomobject]@{
            PSTypeName = 'IntuneScriptLab.Test.Finding'
            PolicyId = $PolicyId
            Severity = $Severity
            RuleName = $Rule
            Message = $Message
        }
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
                '^/beta/deviceManagement/deviceHealthScripts/([^?/]+)(\?|$)' {
                    $tenant.remediations | Where-Object id -eq $Matches[1]
                }
                '^/beta/deviceManagement/deviceManagementScripts\?' { & $summary $tenant.platformScripts }
                '^/beta/deviceManagement/deviceManagementScripts/([^?/]+)/runSummary' {
                    $tenant.runSummaries[$Matches[1]]
                }
                '^/beta/deviceManagement/deviceManagementScripts/([^?/]+)(\?|$)' {
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
        It 'returns the reports under -WhatIf, creates no export job and writes no Markdown' {
            $file = Join-Path $TestDrive 'whatif.md'
            $expected = @(Get-IntuneScriptHealth).Count
            $report = @(Get-IntuneScriptHealth -MarkdownPath $file -WhatIf)

            $expected | Should-BeGreaterThan 0
            $report.Count | Should-Be $expected
            Test-Path -LiteralPath $file | Should-BeFalse
            # Once, for the run without -WhatIf above
            Should-Invoke Get-IslExportReport -ModuleName IntuneScriptLab -Times 1 -Exactly
            # Without the export the apps have no install counts
            ($report | Where-Object PolicyId -eq 'app-a').Succeeded | Should-Be 0
        }

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
            # Unassigned is read from the assignments, not from a finding, so it survives the switch
            $reportOnly = $report | Where-Object PolicyId -eq 'rem-b'
            $reportOnly.Health | Should-Be 'Broken'
            $reportOnly.Notes | Should-BeLikeString '*assigned to nobody*'
            $reportOnly.Errors | Should-Be 0
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
        It 'selects by id alone when no name is given' {
            $report = @(Get-IntuneScriptHealth -Id 'ps-b' -SkipAnalysis -SkipRunState)
            $report.PolicyName | Should-BeCollection @('Set-Proxy')
        }

        It 'passes -Id alone on to the analysis and the drift comparison, without the default name' {
            $null = Get-IntuneScriptHealth -Id 'ps-b' -Path $TestDrive -SkipRunState

            # With Name passed on, its default of '*' selected every policy in those commands
            $byIdAlone = {
                $Id -eq 'ps-b' -and -not $PesterBoundParameters.ContainsKey('Name')
            }
            $invoked = @{
                ModuleName = 'IntuneScriptLab'; Times = 1; Exactly = $true; ParameterFilter = $byIdAlone
            }
            Should-Invoke Test-IntuneDeployedScript @invoked
            Should-Invoke Compare-IntuneDeployedScript @invoked
        }

        It 'passes a -Name the caller gave on to them' {
            $null = Get-IntuneScriptHealth -Name 'Set-*' -SkipRunState

            $invoked = @{
                ModuleName = 'IntuneScriptLab'; Times = 1; Exactly = $true; ParameterFilter = { $Name -eq 'Set-*' }
            }
            Should-Invoke Test-IntuneDeployedScript @invoked
        }

        It 'resolves a relative -MarkdownPath against the PowerShell location' {
            $folder = Join-Path $TestDrive 'relative'
            $null = New-Item -ItemType Directory -Path $folder -Force
            Push-Location $folder
            try { $null = Get-IntuneScriptHealth -MarkdownPath '.\health.md' -SkipAnalysis -SkipRunState }
            finally { Pop-Location }
            Test-Path -LiteralPath (Join-Path $folder 'health.md') | Should-BeTrue
        }
    }

    Context 'Error Handling' {
        It 'ends with the error of the analysis when it fails, and returns no report' {
            Mock Test-IntuneDeployedScript -ModuleName IntuneScriptLab {
                throw 'The analysis could not read Graph.'
            }

            { Get-IntuneScriptHealth -SkipRunState } |
                Should-Throw -ExceptionMessage '*analysis could not read Graph*'
        }

        It 'returns its reports when only the Markdown file cannot be written, and reports that' {
            $missingFolder = Join-Path $TestDrive "no-such-folder-$([guid]::NewGuid().ToString('N'))"
            $healthSplat = @{
                SkipAnalysis = $true; SkipRunState = $true; MarkdownPath = Join-Path $missingFolder 'health.md'
            }

            $output = Get-IntuneScriptHealth @healthSplat -ErrorAction Continue 2>&1
            $errors = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $reports = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })

            $errors | Should-BeCollection -Count 1
            $errors[0].Exception.GetBaseException() |
                Should-HaveType ([System.IO.DirectoryNotFoundException])
            $reports.Count | Should-BeGreaterThan 0
            { Get-IntuneScriptHealth @healthSplat -ErrorAction Stop } | Should-Throw
        }

        It 'leaves a calling script one error and no report when Graph cannot be reached' {
            $run = Invoke-CallerScript -Statement @(
                $script:GraphDown
                "`$reports = @(Get-IntuneScriptHealth -Kind Remediation -SkipRunState)"
                "'reports: ' + `$reports.Count"
            )

            $run.ReachedEnd | Should-BeTrue
            $run.Output | Should-BeCollection @('reports: 0')
            $run.ErrorId | Should-BeCollection @('Graph is down')
        }
    }
}
