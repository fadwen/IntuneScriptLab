function Get-IslAgentLogEvent {
    <#
    .SYNOPSIS
        Names the event an agent log message records, from the lines the experiments identified.

    .DESCRIPTION
        A table of message patterns for the four Intune Management Extension logs, each pattern a
        line that marked a step in the validation rounds (Validation\Findings.md): the script policy
        fetch and its download count, a remediation's schedule inspection, start, detection result
        and report, a Win32 app's policy fetch, applicability, detection, rule evaluation, install
        and report, AgentExecutor's launch, exit code and output, and the Enrollment Status Page's
        phase, selected apps, registrations, tracked install states and completion (round 8).
        Anything else has no event.

        Returns the event name, a Detail string built from the pattern's capture groups (the
        exit code, the detection state, the download count) and the first GUID in the message,
        which is the policy or app id on every line that carries one. The compiled table is kept
        in the module scope as IslAgentLogEvents for Get-IntuneAgentLog -ListEvent.

    .PARAMETER Message
        The log entry's message.

    .EXAMPLE
        Get-IslAgentLogEvent -Message 'Powershell execution is done, exitCode = 1'

        Event ScriptExit with Detail 1.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.AgentLogEvent')]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message
    )

    if (-not $script:IslAgentLogEvents) {
        $definitions = @(
            # IntuneManagementExtension.log: platform scripts and the remediation launches
            @{ Event = 'ScriptPolicyFetch'; Pattern = '\[PowerShell\] (?:Get|After filter, get) (\d+) policies' }
            @{
                Event   = 'ScriptDownloadCount'
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
                Event   = 'ScriptEspPhase'
                Pattern = 'Finished ESP phase check before kicking off PowerShell script\. ESP phase (\w+)'
            }
            @{
                Event   = 'EspNontrackedCheckin'
                Pattern = '\[Flighting\] Key: RunNontrackedAppsCheckinImmediatelyAfterEsp, found value: (\w+)'
            }
            # HealthScripts.log: remediations
            @{ Event = 'RemediationSchedule'; Pattern = '\[HS\] inspect (\w+) schedule for policy' }
            @{
                Event   = 'RemediationQueued'
                Pattern = '\[HS\] Runner : Job is queued and will be scheduled to run at (.+)$'
            }
            @{ Event = 'RemediationStart'; Pattern = '\[HS\] Runner: script \S+ will try to execute now' }
            @{
                Event   = 'DetectionResult'
                Pattern = '\[HS\] the (pre|post)[- ]?rem\w*diation detection script compliance result for \S+ ' +
                    'is (\w+)'
            }
            @{ Event = 'RemediationReport'; Pattern = '\[HS\] new result = \{.*"Result":(\d+)' }
            # AppWorkload.log: Win32 apps
            @{ Event = 'AppPolicyFetch'; Pattern = '^Get policies = \[' }
            @{ Event = 'AppFilteredOut'; Pattern = 'not applicable due to assignment filters' }
            # Relationships (round 6, replayed on the ESP device): apps with a dependency or a
            # supersedence are processed as one subgraph, and their reports carry a ReportingImpact
            @{ Event = 'AppSubgraph'; Pattern = '\[V3Processor\] Processing subgraph with app ids: (.+)$' }
            @{
                Event   = 'AppSubgraphSkipped'
                Pattern = '\[V3Processor\] (Reevaluation interval is not expired|' +
                    'All of the apps in the subgraph require user-context processing)'
            }
            @{
                Event   = 'AppRelationshipReport'
                Pattern = 'Sending status to company portal based on report: \{"ApplicationId":"[^"]+",' +
                    '"ResultantAppState":(\w+),"ReportingImpact":\{"DesiredState":(\d+),"Classification":(\d+),' +
                    '"ConflictReason":(\d+),"ImpactingApps":\[\{"AppId":"([^"]+)"'
            }
            @{ Event = 'AppDependencyToast'; Pattern = '-toast "ToastDependencyAppInstall"' }
            @{
                Event   = 'AppNoIntent'
                Pattern = 'because the app does not have available, required, or uninstall intent'
            }
            @{
                Event   = 'AppDownload'
                Pattern = '\[DownloadActionHandler\] Handler invoked for policy with id: \S+ and version: (\d+)'
            }
            @{
                Event   = 'AppUserContextSkipped'
                Pattern = 'has user install context and this is a userless check-in'
            }
            @{
                Event   = 'AppApplicability'
                Pattern = 'Applicability check for policy with id: \S+ resulted in action status: (\w+) and ' +
                    'applicability state: (\w+)'
            }
            @{
                Event   = 'AppRequirementCheck'
                Pattern = '\[Win32App\] (?:applicationRequirementMetadata|RequiredOSArchitecture).*' +
                    '(?:applicability|skip check)[:.]? ?(\w*)'
            }
            @{ Event = 'AppRequirementScript'; Pattern = 'result of requirementMet: (\w+)' }
            @{
                Event   = 'AppDetection'
                Pattern = 'Detection for policy with id: \S+ resulted in action status: (\w+) and ' +
                    'detection state: (\w+)'
            }
            @{
                Event   = 'AppDetectionRule'
                Pattern = '(?:Checked (?:filePath|reg path|Powershell script)|Path doesn''t exists|' +
                    'actualV\w+:).*applicationDetected: (\w+)'
            }
            @{ Event = 'AppExecution'; Pattern = 'Handler invoked with execution type: (\w+) for policy with id' }
            @{ Event = 'AppInstallExit'; Pattern = '\[Win32App\] lpExitCode (-?\d+)$' }
            @{ Event = 'AppInstallOutcome'; Pattern = '\[Win32App\] lpExitCode is defined as (\w+)' }
            @{
                Event   = 'AppReport'
                Pattern = 'Sending status to company portal based on report: \{"ApplicationId":"[^"]+",' +
                    '"ResultantAppState":(\w+)'
            }
            # AppWorkload.log: the Enrollment Status Page (Findings, "The Enrollment Status Page")
            @{ Event = 'EspPhase'; Pattern = '\[Win32App\] The EspPhase: (\w+)' }
            @{
                Event   = 'EspAppsSelected'
                Pattern = '\[ESPAppLockInProcessor\] Found (\d+) apps which need to be installed for current phase'
            }
            @{
                Event   = 'EspAppRegistered'
                Pattern = '\[EspManager\] In EspPhase: (\w+)\. App \S+ has been registered.*App name: (.+?)\.?$'
            }
            @{
                Event   = 'EspAppState'
                Pattern = '\[EspManager\] Updating ESP tracked install status from (\w+) to (\w+) for application'
            }
            @{
                Event   = 'EspPhaseComplete'
                Pattern = '\[CheckDeviceAndAccountSetupStateWithWmi\] [Aa]ll apps completed for (\w+)'
            }
            @{ Event = 'EspComplete'; Pattern = 'ESP completed\. Triggering immediate app workload check-in' }
            # AgentExecutor.log: the process that runs every script
            @{ Event = 'ExecutorStart'; Pattern = '^Prepare to run Powershell Script' }
            @{ Event = 'ExecutorExit'; Pattern = '^Powershell exit code is (-?\d+)' }
            @{
                # The line carries stdout and stderr together: "output = <out>, error = <err>"
                Event   = 'ExecutorOutput'
                Pattern = '^write output done\. output = (.*?)(?:\r?\n?, error = (.*))?$'
            }
            @{ Event = 'ExecutorError'; Pattern = '^error from script =(.*)$' }
        )
        $singleline = [System.Text.RegularExpressions.RegexOptions]::Singleline
        $script:IslAgentLogEvents = @(foreach ($definition in $definitions) {
                [pscustomobject]@{
                    Event = $definition.Event
                    Regex = [regex]::new($definition.Pattern, $singleline)
                }
            })
    }

    $eventName = $null
    $detail = $null
    foreach ($candidate in $script:IslAgentLogEvents) {
        $match = $candidate.Regex.Match($Message)
        if (-not $match.Success) { continue }
        $eventName = $candidate.Event
        $groups = @(for ($i = 1; $i -lt $match.Groups.Count; $i++) { $match.Groups[$i].Value.Trim() })
        $detail = ($groups | Where-Object { $_ }) -join ' '
        if (-not $detail) { $detail = $null }
        break
    }
    # The policy or app id is the first GUID that is not the empty one: the device's user id on a
    # userless check-in is 00000000-... and comes before the policy id on some lines
    $guidPattern = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
    $id = $null
    foreach ($match in [regex]::Matches($Message, $guidPattern)) {
        $candidate = $match.Value.ToLower()
        if ($null -eq $id) { $id = $candidate }
        if ($candidate -ne '00000000-0000-0000-0000-000000000000') { $id = $candidate; break }
    }

    [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.AgentLogEvent'
        Event      = $eventName
        Detail     = $detail
        Id         = $id
    }
}
