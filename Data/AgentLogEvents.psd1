# The events of the Intune Management Extension logs: each pattern a line that marked a step in
# the validation rounds (Validation\Findings.md). Get-IslAgentLogEvent compiles them, in this
# order, into one expression; where two fit the same text, the earlier one wins.
@{
    Definitions = @(
        # IntuneManagementExtension.log: platform scripts and the remediation launches
        @{ Event = 'ScriptPolicyFetch'; Pattern = '\[PowerShell\] (?:Get|After filter, get) (\d+) policies' }
        @{
            Event = 'ScriptDownloadCount'
            Pattern = '\[PowerShell\] Policy \S+ for user \S+ has download count = (\d+)'
        }
        @{ Event = 'ScriptPolicyStart'; Pattern = '\[PowerShell\] Processing policy with id = (\S+)' }
        @{ Event = 'ScriptPolicyResult'; Pattern = '\[PowerShell\] User Id = .* policy result = (\w+)' }
        @{ Event = 'ScriptExit'; Pattern = 'Powershell execution is done, exitCode = (-?\d+)' }
        @{ Event = 'ScriptLaunch'; Pattern = 'Launch powershell executor in (\w+) session' }
        @{ Event = 'UserContextSkipped'; Pattern = 'This is not AADJ/HAADJ device, skip user context' }
        @{ Event = 'AgentStart'; Pattern = 'first check in on start' }
        @{ Event = 'UserlessCheckin'; Pattern = 'Userless session, skip UserToken for device check-in' }
        @{
            Event = 'ScriptEspPhase'
            Pattern = 'Finished ESP phase check before kicking off PowerShell script\. ESP phase (\w+)'
        }
        @{
            Event = 'EspNontrackedCheckin'
            Pattern = '\[Flighting\] Key: RunNontrackedAppsCheckinImmediatelyAfterEsp, found value: (\w+)'
        }
        # HealthScripts.log: remediations
        @{ Event = 'RemediationSchedule'; Pattern = '\[HS\] inspect (\w+) schedule for policy' }
        @{
            Event = 'RemediationQueued'
            Pattern = '\[HS\] Runner : Job is queued and will be scheduled to run at (.+)$'
        }
        @{ Event = 'RemediationStart'; Pattern = '\[HS\] Runner: script \S+ will try to execute now' }
        @{
            Event = 'DetectionResult'
            Pattern = @(
                '\[HS\] the (pre|post)[- ]?rem\w*diation detection script compliance result for \S+ '
                'is (\w+)'
            )
        }
        @{ Event = 'RemediationReport'; Pattern = '\[HS\] new result = \{.*"Result":(\d+)' }
        # AppWorkload.log: Win32 apps
        @{ Event = 'AppPolicyFetch'; Pattern = '^Get policies = \[' }
        @{ Event = 'AppFilteredOut'; Pattern = 'not applicable due to assignment filters' }
        # Relationships (round 6, replayed on the ESP device): apps with a dependency or a
        # supersedence are processed as one subgraph, and their reports carry a ReportingImpact
        @{ Event = 'AppSubgraph'; Pattern = '\[V3Processor\] Processing subgraph with app ids: (.+)$' }
        @{
            Event = 'AppSubgraphSkipped'
            Pattern = @(
                '\[V3Processor\] (Reevaluation interval is not expired|'
                'All of the apps in the subgraph require user-context processing)'
            )
        }
        @{
            Event = 'AppRelationshipReport'
            Pattern = @(
                'Sending status to company portal based on report: \{"ApplicationId":"[^"]+",'
                '"ResultantAppState":(\w+),"ReportingImpact":\{"DesiredState":(\d+),'
                '"Classification":(\d+),'
                '"ConflictReason":(\d+),"ImpactingApps":\[\{"AppId":"([^"]+)"'
            )
        }
        @{ Event = 'AppDependencyToast'; Pattern = '-toast "ToastDependencyAppInstall"' }
        @{
            Event = 'AppNoIntent'
            Pattern = 'because the app does not have available, required, or uninstall intent'
        }
        @{
            Event = 'AppDownload'
            Pattern = '\[DownloadActionHandler\] Handler invoked for policy with id: \S+ and version: (\d+)'
        }
        @{
            Event = 'AppUserContextSkipped'
            Pattern = 'has user install context and this is a userless check-in'
        }
        @{
            Event = 'AppApplicability'
            Pattern = @(
                'Applicability check for policy with id: \S+ resulted in action status: (\w+) and '
                'applicability state: (\w+)'
            )
        }
        @{
            Event = 'AppRequirementCheck'
            Pattern = @(
                '\[Win32App\] (?:applicationRequirementMetadata|RequiredOSArchitecture).*'
                '(?:applicability|skip check)[:.]? ?(\w*)'
            )
        }
        @{ Event = 'AppRequirementScript'; Pattern = 'result of requirementMet: (\w+)' }
        @{
            Event = 'AppDetection'
            Pattern = @(
                'Detection for policy with id: \S+ resulted in action status: (\w+) and '
                'detection state: (\w+)'
            )
        }
        @{
            Event = 'AppDetectionRule'
            Pattern = @(
                '(?:Checked (?:filePath|reg path|Powershell script)|Path doesn''t exists|'
                'actualV\w+:).*applicationDetected: (\w+)'
            )
        }
        @{ Event = 'AppExecution'; Pattern = 'Handler invoked with execution type: (\w+) for policy with id' }
        @{ Event = 'AppInstallExit'; Pattern = '\[Win32App\] lpExitCode (-?\d+)$' }
        @{ Event = 'AppInstallOutcome'; Pattern = '\[Win32App\] lpExitCode is defined as (\w+)' }
        @{
            Event = 'AppReport'
            Pattern = @(
                'Sending status to company portal based on report: \{"ApplicationId":"[^"]+",'
                '"ResultantAppState":(\w+)'
            )
        }
        # AppWorkload.log: the Enrollment Status Page (Findings, "The Enrollment Status Page")
        @{ Event = 'EspPhase'; Pattern = '\[Win32App\] The EspPhase: (\w+)' }
        @{
            Event = 'EspAppsSelected'
            Pattern = '\[ESPAppLockInProcessor\] Found (\d+) apps which need to be installed for current phase'
        }
        @{
            Event = 'EspAppRegistered'
            Pattern = '\[EspManager\] In EspPhase: (\w+)\. App \S+ has been registered.*App name: (.+?)\.?$'
        }
        @{
            Event = 'EspAppState'
            Pattern = '\[EspManager\] Updating ESP tracked install status from (\w+) to (\w+) for application'
        }
        @{
            Event = 'EspPhaseComplete'
            Pattern = '\[CheckDeviceAndAccountSetupStateWithWmi\] [Aa]ll apps completed for (\w+)'
        }
        @{ Event = 'EspComplete'; Pattern = 'ESP completed\. Triggering immediate app workload check-in' }
        # AgentExecutor.log: the process that runs every script
        @{ Event = 'ExecutorStart'; Pattern = '^Prepare to run Powershell Script' }
        @{ Event = 'ExecutorExit'; Pattern = '^Powershell exit code is (-?\d+)' }
        @{
            # The line carries stdout and stderr together: "output = <out>, error = <err>"
            Event = 'ExecutorOutput'
            Pattern = '^write output done\. output = (.*?)(?:\r?\n?, error = (.*))?$'
        }
        @{ Event = 'ExecutorError'; Pattern = '^error from script =(.*)$' }
    )
}
