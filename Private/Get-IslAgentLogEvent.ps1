function Get-IslAgentLogEvent {
    <#
    .SYNOPSIS
        Names the event that an agent log message records, as the experiments found.

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
        The log entries' messages; one result per message, in the same order. A call per entry
        costs more than the classification, so Get-IntuneAgentLog sends a log's messages in one.

    .EXAMPLE
        Get-IslAgentLogEvent -Message 'Powershell execution is done, exitCode = 1'

        Event ScriptExit with Detail 1.

    .INPUTS
        None.

    .OUTPUTS
        IntuneScriptLab.AgentLogEvent.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.AgentLogEvent')]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [string[]]$Message
    )

    if (-not $script:IslAgentLogEvents) {
        $definitions = @(
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
                Event = 'AppSubgraphSkipped'
                Pattern = '\[V3Processor\] (Reevaluation interval is not expired|' +
                'All of the apps in the subgraph require user-context processing)'
            }
            @{
                Event = 'AppRelationshipReport'
                Pattern = 'Sending status to company portal based on report: \{"ApplicationId":"[^"]+",' +
                '"ResultantAppState":(\w+),"ReportingImpact":\{"DesiredState":(\d+),"Classification":(\d+),' +
                '"ConflictReason":(\d+),"ImpactingApps":\[\{"AppId":"([^"]+)"'
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
                Pattern = 'Applicability check for policy with id: \S+ resulted in action status: (\w+) and ' +
                'applicability state: (\w+)'
            }
            @{
                Event = 'AppRequirementCheck'
                Pattern = '\[Win32App\] (?:applicationRequirementMetadata|RequiredOSArchitecture).*' +
                '(?:applicability|skip check)[:.]? ?(\w*)'
            }
            @{ Event = 'AppRequirementScript'; Pattern = 'result of requirementMet: (\w+)' }
            @{
                Event = 'AppDetection'
                Pattern = 'Detection for policy with id: \S+ resulted in action status: (\w+) and ' +
                'detection state: (\w+)'
            }
            @{
                Event = 'AppDetectionRule'
                Pattern = '(?:Checked (?:filePath|reg path|Powershell script)|Path doesn''t exists|' +
                'actualV\w+:).*applicationDetected: (\w+)'
            }
            @{ Event = 'AppExecution'; Pattern = 'Handler invoked with execution type: (\w+) for policy with id' }
            @{ Event = 'AppInstallExit'; Pattern = '\[Win32App\] lpExitCode (-?\d+)$' }
            @{ Event = 'AppInstallOutcome'; Pattern = '\[Win32App\] lpExitCode is defined as (\w+)' }
            @{
                Event = 'AppReport'
                Pattern = 'Sending status to company portal based on report: \{"ApplicationId":"[^"]+",' +
                '"ResultantAppState":(\w+)'
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
        # One expression for the whole table: 44 patterns tried one by one cost 44 statements a
        # message, which was most of what reading a log cost; one Match is one. Alternation keeps
        # the table's order at a given position, so two patterns that fit the same text still
        # resolve to the earlier one
        $singleline = [System.Text.RegularExpressions.RegexOptions]::Singleline
        $combined = [System.Text.StringBuilder]::new()
        $position = 0
        $script:IslAgentLogEvents = @(foreach ($definition in $definitions) {
                # The literal text a pattern starts with, which a matching message must contain
                # somewhere: cheaper to look for than to run the pattern, and most messages match
                # no pattern at all
                $prefix = Get-IslRegexLiteralPrefix -Pattern $definition.Pattern
                $group = "e$position"
                $renamed = ConvertTo-IslNamedGroupPattern -Pattern $definition.Pattern -Prefix "${group}g"
                if ($position -gt 0) { $null = $combined.Append('|') }
                $null = $combined.Append("(?<$group>").Append($renamed.Pattern).Append(')')
                $position++
                [pscustomobject]@{
                    Event = $definition.Event
                    Regex = [regex]::new($definition.Pattern, $singleline)
                    Needle = if ($prefix.Length -ge 3) { $prefix } else { $null }
                    Group = $group
                    Captures = $renamed.Count
                }
            })
        $script:IslAgentLogEventByGroup = @{}
        foreach ($definition in $script:IslAgentLogEvents) {
            $script:IslAgentLogEventByGroup[$definition.Group] = $definition
        }
        $compiled = $singleline -bor [System.Text.RegularExpressions.RegexOptions]::Compiled
        $script:IslAgentLogEventRegex = [regex]::new($combined.ToString(), $compiled)
    }

    $combinedRegex = $script:IslAgentLogEventRegex
    $byGroup = $script:IslAgentLogEventByGroup
    $firstSuccess = $script:IslAgentLogFirstSuccess
    # The policy or app id is the first GUID that is not the empty one: the device's user id on a
    # userless check-in is 00000000-... and comes before the policy id on some lines
    $guidRegex = $script:IslAgentLogGuidRegex
    foreach ($text in $Message) {
        $eventName = $null
        $detail = $null
        $match = $combinedRegex.Match($text)
        if ($match.Success) {
            # Group 0 is the whole match; the first successful group after it is the alternative
            $winner = & $firstSuccess $match.Groups
            $definition = $byGroup[$winner.Name]
            $eventName = $definition.Event
            $groups = @(for ($i = 1; $i -le $definition.Captures; $i++) {
                    $match.Groups["$($definition.Group)g$i"].Value.Trim()
                })
            $detail = ($groups | Where-Object { $_ }) -join ' '
            if (-not $detail) { $detail = $null }
        }
        $id = $null
        # A GUID has four hyphens; a message without one has no id to look for
        if ($text.IndexOf('-') -ge 0) {
            foreach ($match in $guidRegex.Matches($text)) {
                $candidate = $match.Value.ToLower()
                if ($null -eq $id) { $id = $candidate }
                if ($candidate -ne '00000000-0000-0000-0000-000000000000') { $id = $candidate; break }
            }
        }

        [pscustomobject]@{
            PSTypeName = 'IntuneScriptLab.AgentLogEvent'
            Event = $eventName
            Detail = $detail
            Id = $id
        }
    }
}


# The event table, compiled by the first call of Get-IslAgentLogEvent. It is assigned here so
# that the test for it in the function reads a variable that exists, which strict mode requires.
$script:IslAgentLogEvents = $null

$script:IslAgentLogGuidRegex = [regex]::new(
    '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
    [System.Text.RegularExpressions.RegexOptions]::Compiled)

# The first group after group 0 that took part in a match, found without a PowerShell loop over the
# groups: Enumerable.Skip(1) then FirstOrDefault with Group.Success as the predicate. The generic
# methods are closed by reflection once, because Windows PowerShell 5.1 has no syntax for it, and
# GroupCollection is cast to IEnumerable<Group> first because .NET Framework's is not one
$script:IslAgentLogFirstSuccess = & {
    $groupType = [System.Text.RegularExpressions.Group]
    $enumerable = [System.Linq.Enumerable]
    $cast = $enumerable.GetMethod('Cast').MakeGenericMethod($groupType)
    $skip = ($enumerable.GetMethods() | Where-Object {
            $_.Name -eq 'Skip' -and $_.GetParameters()[1].ParameterType -eq [int]
        } | Select-Object -First 1).MakeGenericMethod($groupType)
    $first = ($enumerable.GetMethods() | Where-Object {
            $_.Name -eq 'FirstOrDefault' -and $_.GetParameters().Count -eq 2 -and
            $_.GetParameters()[1].ParameterType.Name -like 'Func*'
        } | Select-Object -First 1).MakeGenericMethod($groupType)
    $success = [System.Delegate]::CreateDelegate([System.Func[System.Text.RegularExpressions.Group, bool]],
        $groupType.GetProperty('Success').GetGetMethod())
    {
        param($Groups)
        # Argument arrays built by hand: PowerShell would enumerate the collection into @()
        $castArguments = [object[]]::new(1)
        $castArguments[0] = $Groups
        $skipArguments = [object[]]::new(2)
        $skipArguments[0] = $cast.Invoke($null, $castArguments)
        $skipArguments[1] = 1
        $firstArguments = [object[]]::new(2)
        $firstArguments[0] = $skip.Invoke($null, $skipArguments)
        $firstArguments[1] = $success
        $first.Invoke($null, $firstArguments)
    }.GetNewClosure()
}
