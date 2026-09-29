#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Per-policy timelines over a fake log folder: a remediation's fetch, start, verdict and report,
    a Win32 app's detection, install and report (named from the policy list the agent logs) and a
    platform script's start and result, grouped by id with their outcome, run count and summary.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force

    function script:New-CmTraceLine {
        param([string]$Message, [string]$Time, [string]$Date = '9-25-2026', [int]$Type = 1,
            [string]$Component = 'IntuneManagementExtension', [int]$Thread = 4)
        "<![LOG[$Message]LOG]!><time=`"$Time`" date=`"$Date`" component=`"$Component`" context=`"`" " +
        "type=`"$Type`" thread=`"$Thread`" file=`"`">"
    }
    function script:Write-TestLog {
        param([string]$Folder, [string]$Name, [string[]]$Lines)
        $null = New-Item -ItemType Directory -Path $Folder -Force
        $path = Join-Path $Folder $Name
        $content = ($Lines -join "`r`n") + "`r`n"
        [System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))
        $path
    }
    $script:Policy = 'bbf7e139-fe9d-4783-80df-627b8e084059'
    $script:App = '9b6543c3-6d66-4cfb-a8fb-d780079278f6'
    $script:Script = 'f783f0ab-4bfa-4586-8290-33b8b3b34c74'
    $script:Logs = Join-Path $TestDrive 'Logs'
    $hs = @{ Component = 'HealthScripts' }
    $aw = @{ Component = 'AppWorkload' }
    Write-TestLog $script:Logs 'HealthScripts.log' @(
        New-CmTraceLine @hs -Time '08:40:13.0000000' -Message ("[HS] inspect hourly schedule for policy " +
            "$($script:Policy): UTC = False, Interval = 1, Time = ")
        New-CmTraceLine @hs -Time '08:40:14.0000000' -Message ('[HS] Runner : Job is queued and will be ' +
            'scheduled to run at UTC 9/25/2026 8:45:14 AM.')
        New-CmTraceLine @hs -Time '08:45:14.0000000' -Message ("[HS] Runner: script $($script:Policy) will try " +
            'to execute now.')
        New-CmTraceLine @hs -Time '08:45:26.0000000' -Message ('[HS] the pre-remdiation detection script ' +
            "compliance result for $($script:Policy) is False")
        New-CmTraceLine @hs -Time '08:46:56.0000000' -Message ('[HS] new result = {"PolicyId":"' + $script:Policy +
            '","UserId":"00000000-0000-0000-0000-000000000000","PolicyHash":null,"Result":4,"ResultDetails":"{}"}')
    )
    Write-TestLog $script:Logs 'AppWorkload.log' @(
        New-CmTraceLine @aw -Time '08:38:00.0000000' -Message ('Get policies = [{"Id":"' + $script:App +
            '","Name":"Widget 2.0","Version":1,"Intent":3}]')
        New-CmTraceLine @aw -Time '08:38:04.0000000' -Message ('[Win32App][DetectionActionHandler] Detection ' +
            "for policy with id: $($script:App) resulted in action status: Success and detection state: " +
            'NotDetected.')
        New-CmTraceLine @aw -Time '08:38:20.0000000' -Message ('[Win32App][ExecutionActionHandler] Handler ' +
            "invoked with execution type: Install for policy with id: $($script:App) and version: 1.")
        New-CmTraceLine @aw -Time '08:38:40.0000000' -Message '[Win32App] lpExitCode is defined as Success'
        New-CmTraceLine @aw -Time '08:38:45.0000000' -Message ('[Win32App][ReportingManager] Sending status to ' +
            'company portal based on report: {"ApplicationId":"' + $script:App + '","ResultantAppState":1,' +
            '"ReportingImpact":{}}')
    )
    Write-TestLog $script:Logs 'IntuneManagementExtension.log' @(
        New-CmTraceLine -Time '08:40:10.0000000' -Message ('[PowerShell] Processing policy with id = ' +
            $script:Script)
        New-CmTraceLine -Time '08:40:30.0000000' -Message ('[PowerShell] User Id = 00000000-0000-0000-0000-' +
            "000000000000, Policy id = $($script:Script), policy result = Failed")
    )
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Get-IntuneAgentTimeline' -Tag 'Unit', 'Public' {

    Context 'Core Functionality' {
        BeforeAll {
            $script:Timelines = @(Get-IntuneAgentTimeline -Path $script:Logs)
        }

        It 'builds one typed timeline per id, oldest first' {
            $script:Timelines.Count | Should-Be 3
            $script:Timelines[0].PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.AgentTimeline'
            @($script:Timelines.Id) | Should-BeCollection @($script:App, $script:Script, $script:Policy)
        }

        It 'tells a remediation''s story from the schedule inspection to the report' {
            $remediation = $script:Timelines | Where-Object Id -eq $script:Policy
            $remediation.Kind | Should-Be 'Remediation'
            $remediation.Name | Should-Be $script:Policy
            $remediation.Runs | Should-Be 1
            $remediation.Outcome | Should-Be 'RemediationReport 4'
            $remediation.Started.ToString('HH:mm:ss') | Should-Be '08:40:13'
            $remediation.Ended.ToString('HH:mm:ss') | Should-Be '08:46:56'
            $remediation.Duration.TotalSeconds | Should-Be 403
            @($remediation.Steps).Count | Should-Be 4
            $remediation.Steps[0].PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.AgentTimelineStep'
            $expectedEvents = 'RemediationSchedule', 'RemediationStart', 'DetectionResult', 'RemediationReport'
            @($remediation.Steps.Event) | Should-BeCollection $expectedEvents
            $remediation.Summary |
                Should-Be ('08:40:13 RemediationSchedule hourly > 08:45:14 RemediationStart > ' +
                    '08:45:26 DetectionResult pre False > 08:46:56 RemediationReport 4')
        }

        It 'names an app from the policy list and counts its install as a run' {
            $app = $script:Timelines | Where-Object Id -eq $script:App
            $app.Kind | Should-Be 'Win32App'
            $app.Name | Should-Be 'Widget 2.0'
            $app.Runs | Should-Be 1
            $app.Outcome | Should-Be 'AppReport 1'
            # The install outcome line carries no id, so it is not a step of the app
            $expectedEvents = 'AppPolicyFetch', 'AppDetection', 'AppExecution', 'AppReport'
            @($app.Steps.Event) | Should-BeCollection $expectedEvents
        }

        It 'reads a platform script from the agent log' {
            $platform = $script:Timelines | Where-Object Id -eq $script:Script
            $platform.Kind | Should-Be 'PlatformScript'
            $platform.Runs | Should-Be 1
            $platform.Outcome | Should-Be 'ScriptPolicyResult Failed'
            $platform.Duration.TotalSeconds | Should-Be 20
        }
    }

    Context 'Filters' {
        It 'keeps to the ids and logs asked for' {
            @(Get-IntuneAgentTimeline -Path $script:Logs -Id $script:App).Id | Should-BeCollection @($script:App)
            $health = @(Get-IntuneAgentTimeline -Path $script:Logs -Log HealthScripts)
            $health.Id | Should-BeCollection @($script:Policy)
        }

        It 'keeps -Id to the timeline whose own id it is, and takes a relationship report as the outcome' {
            $other = '1a2b3c4d-0000-4000-8000-000000000002'
            $logs = Join-Path $TestDrive 'RelationLogs'
            $aw = @{ Component = 'AppWorkload' }
            Write-TestLog $logs 'AppWorkload.log' @(
                New-CmTraceLine @aw -Time '09:00:00.0000000' -Message ('[Win32App][DetectionActionHandler] ' +
                    "Detection for policy with id: $($script:App) resulted in action status: Success and " +
                    'detection state: NotDetected.')
                New-CmTraceLine @aw -Time '09:00:05.0000000' -Message ('[Win32App][DetectionActionHandler] ' +
                    "Detection for policy with id: $other resulted in action status: Success and " +
                    'detection state: Detected.')
                # Names both apps: the report is about the first, the second is the impacting app
                New-CmTraceLine @aw -Time '09:00:10.0000000' -Message ('[Win32App][ReportingManager] Sending ' +
                    'status to company portal based on report: {"ApplicationId":"' + $script:App +
                    '","ResultantAppState":1,"ReportingImpact":{"DesiredState":1,"Classification":1,' +
                    '"ConflictReason":0,"ImpactingApps":[{"AppId":"' + $other + '"}]}}')
            ) | Out-Null
            $timelines = @(Get-IntuneAgentTimeline -Path $logs -Id $other)
            @($timelines.Id) | Should-BeCollection @($other)
            $first = @(Get-IntuneAgentTimeline -Path $logs -Id $script:App)
            $first.Count | Should-Be 1
            $first[0].Outcome | Should-BeLikeString 'AppRelationshipReport*'
        }

        It 'cuts the steps by time' {
            $lateSplat = @{ Path = $script:Logs; Id = $script:Policy; After = [datetime]'2026-09-25 08:45:00' }
            $late = Get-IntuneAgentTimeline @lateSplat
            @($late.Steps).Count | Should-Be 3
            $late.Started.ToString('HH:mm:ss') | Should-Be '08:45:14'
        }

        It 'returns nothing for a folder without known lines' {
            $empty = Join-Path $TestDrive 'Empty'
            Write-TestLog $empty 'HealthScripts.log' @(New-CmTraceLine -Message 'noise' -Time '01:00:00.0000000')
            @(Get-IntuneAgentTimeline -Path $empty).Count | Should-Be 0
        }
    }
}
