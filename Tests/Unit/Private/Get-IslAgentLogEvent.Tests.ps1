#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The event table, each case a line taken from the agent logs of the validation rounds
    (Validation\Findings.md and the collected Results): the event it names, the detail it extracts
    and the policy or app id it finds.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    $script:Policy = 'bbf7e139-fe9d-4783-80df-627b8e084059'
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Get-IslAgentLogEvent' -Tag 'Unit', 'Private' {

    It 'names <Event> with detail <Detail>' -ForEach @(
        @{ Message = '[PowerShell] Get 25 policies'; Event = 'ScriptPolicyFetch'; Detail = '25' }
        @{ Message = '[PowerShell] After filter, get 0 policies'; Event = 'ScriptPolicyFetch'; Detail = '0' }
        @{
            Message = '[PowerShell] Policy f783f0ab-4bfa-4586-8290-33b8b3b34c74 for user ' +
                '00000000-0000-0000-0000-000000000000 has download count = 3'
            Event   = 'ScriptDownloadCount'; Detail = '3'
        }
        @{
            Message = '[PowerShell] Processing policy with id = f783f0ab-4bfa-4586-8290-33b8b3b34c74'
            Event   = 'ScriptPolicyStart'; Detail = 'f783f0ab-4bfa-4586-8290-33b8b3b34c74'
        }
        @{
            Message = '[PowerShell] User Id = 00000000-0000-0000-0000-000000000000, Policy id = ' +
                'f783f0ab-4bfa-4586-8290-33b8b3b34c74, policy result = Failed'
            Event   = 'ScriptPolicyResult'; Detail = 'Failed'
        }
        @{ Message = 'Powershell execution is done, exitCode = 1'; Event = 'ScriptExit'; Detail = '1' }
        @{ Message = 'Launch powershell executor in machine session'; Event = 'ScriptLaunch'; Detail = 'machine' }
        @{
            Message = '[PowerShell] This is not AADJ/HAADJ device, skip user context for ' +
                '7c71b68e-34a5-4d05-bc5d-3d642b13f5e3'
            Event   = 'UserContextSkipped'; Detail = $null
        }
        @{
            Message = '[HS] inspect hourly schedule for policy bbf7e139-fe9d-4783-80df-627b8e084059: ' +
                'UTC = False, Interval = 1, Time = '
            Event   = 'RemediationSchedule'; Detail = 'hourly'
        }
        @{
            Message = '[HS] Runner : Job is queued and will be scheduled to run at UTC 9/25/2026 8:45:14 AM.'
            Event   = 'RemediationQueued'; Detail = 'UTC 9/25/2026 8:45:14 AM.'
        }
        @{
            Message = '[HS] Runner: script bbf7e139-fe9d-4783-80df-627b8e084059 will try to execute now.'
            Event   = 'RemediationStart'; Detail = $null
        }
        @{
            Message = '[HS] the pre-remdiation detection script compliance result for ' +
                'bbf7e139-fe9d-4783-80df-627b8e084059 is False'
            Event   = 'DetectionResult'; Detail = 'pre False'
        }
        @{
            Message = '[HS] new result = {"PolicyId":"bbf7e139-fe9d-4783-80df-627b8e084059","UserId":' +
                '"00000000-0000-0000-0000-000000000000","PolicyHash":null,"Result":4,"ResultDetails":"{}"}'
            Event   = 'RemediationReport'; Detail = '4'
        }
        @{
            Message = 'Get policies = [{"Id":"9b6543c3-6d66-4cfb-a8fb-d780079278f6","Name":"ISL-W32-DEP-PARENT"}]'
            Event   = 'AppPolicyFetch'; Detail = $null
        }
        @{
            Message = '[Win32App][V3Processor] All apps in the subgraph are not applicable due to assignment ' +
                'filters. Skipping processing.'
            Event   = 'AppFilteredOut'; Detail = $null
        }
        @{
            Message = '[Win32Apps] App policy with id: 9b6543c3-6d66-4cfb-a8fb-d780079278f6 will not be ' +
                'evaluated as it has user install context and this is a userless check-in. The app will ' +
                'be reported as not applicable.'
            Event   = 'AppUserContextSkipped'; Detail = $null
        }
        @{
            Message = '[Win32App][ApplicabilityActionHandler] Applicability check for policy with id: ' +
                '9b6543c3-6d66-4cfb-a8fb-d780079278f6 resulted in action status: Success and ' +
                'applicability state: Applicable.'
            Event   = 'AppApplicability'; Detail = 'Success Applicable'
        }
        @{
            Message = '[Win32App] RequiredOSArchitecture: 96,is64BitOperatingSystem: True,' +
                'AllowedArchitectures: X64, X86,applicability: ApplicableBuild: 26100.'
            Event   = 'AppRequirementCheck'; Detail = 'ApplicableBuild'
        }
        @{
            Message = '[Win32App] applicationRequirementMetadata.RequiredMemory is , skip check.'
            Event   = 'AppRequirementCheck'; Detail = $null
        }
        @{
            Message = '[Win32App] Checked Powershell script exitCode: 0 ... result of requirementMet: True'
            Event   = 'AppRequirementScript'; Detail = 'True'
        }
        @{
            Message = '[Win32App][DetectionActionHandler] Detection for policy with id: ' +
                '9b6543c3-6d66-4cfb-a8fb-d780079278f6 resulted in action status: Success and ' +
                'detection state: NotDetected.'
            Event   = 'AppDetection'; Detail = 'Success NotDetected'
        }
        @{
            Message = '[Win32App] Checked filePath: C:\ProgramData\IntuneScriptLab\Fixtures\present.txt, ' +
                'Exists: True, applicationDetected: True'
            Event   = 'AppDetectionRule'; Detail = 'True'
        }
        @{
            Message = '[Win32App] Checked reg path: HKEY_LOCAL_MACHINE\SOFTWARE\IntuneScriptLab, name: ' +
                'Version, operator: 8, type: 5, value: 9.0 , result of applicationDetected: False'
            Event   = 'AppDetectionRule'; Detail = 'False'
        }
        @{
            Message = "[Win32App] Path doesn't exists: C:\ProgramData\IntuneScriptLab\Fixtures\missing.txt " +
                'applicationDetected: False'
            Event   = 'AppDetectionRule'; Detail = 'False'
        }
        @{
            Message = '[Win32App] LessThan: actualVersion: 10.0.1, detectionVersion: 9.0, ' +
                'applicationDetected: False'
            Event   = 'AppDetectionRule'; Detail = 'False'
        }
        @{
            Message = '[Win32App] Checked Powershell script exitCode: 1 EnforceSignatureCheck: 1 RunAs32Bit: 0 ' +
                'InstallExRunAs: 1, result of applicationDetected: False'
            Event   = 'AppDetectionRule'; Detail = 'False'
        }
        @{
            Message = '[Win32App][ExecutionActionHandler] Handler invoked with execution type: Install for ' +
                'policy with id: 9b6543c3-6d66-4cfb-a8fb-d780079278f6 and version: 1.'
            Event   = 'AppExecution'; Detail = 'Install'
        }
        @{
            Message = '[Win32App][V3Processor] Processing subgraph with app ids: ' +
                '339c2bfa-1111-4cfb-a8fb-d780079278f6, 99a4be69-2222-4cfb-a8fb-d780079278f6'
            Event   = 'AppSubgraph'
            Detail  = '339c2bfa-1111-4cfb-a8fb-d780079278f6, 99a4be69-2222-4cfb-a8fb-d780079278f6'
        }
        @{
            Message = '[Win32App][V3Processor] Reevaluation interval is not expired for subgraph ' +
                '9b6543c3-6d66-4cfb-a8fb-d780079278f6 and no override condition applies. Skipping processing.'
            Event   = 'AppSubgraphSkipped'; Detail = 'Reevaluation interval is not expired'
        }
        @{
            Message = '[Win32App][V3Processor] All of the apps in the subgraph require user-context processing, ' +
                'and the target user is not logged in. Skipping processing.'
            Event   = 'AppSubgraphSkipped'
            Detail  = 'All of the apps in the subgraph require user-context processing'
        }
        @{
            Message = '[Win32App][ReportingManager] Sending status to company portal based on report: ' +
                '{"ApplicationId":"ec9586f0-3333-4cfb-a8fb-d780079278f6","ResultantAppState":3,' +
                '"ReportingImpact":{"DesiredState":3,"Classification":1,"ConflictReason":2,"ImpactingApps":' +
                '[{"AppId":"b107041b-4444-4cfb-a8fb-d780079278f6","RelationshipType":0}]},"ReportingImpact2":{}}'
            Event   = 'AppRelationshipReport'; Detail = '3 3 1 2 b107041b-4444-4cfb-a8fb-d780079278f6'
        }
        @{
            Message = '[Win32App] Toast message with: "C:\Program Files (x86)\Microsoft Intune Management ' +
                'Extension\agentexecutor.exe"  -toast "ToastDependencyAppInstall" "SVNM" "eyJDb"'
            Event   = 'AppDependencyToast'; Detail = $null
        }
        @{
            Message = '[Win32App][ReportingManager] Not sending status update for user with id: ' +
                'c3b8cf61-fac9-4450-943e-f6a246d9c7e6 and app: 99a4be69-2222-4cfb-a8fb-d780079278f6 because ' +
                'the app does not have available, required, or uninstall intent.'
            Event   = 'AppNoIntent'; Detail = $null
        }
        @{
            Message = '[Win32App][DownloadActionHandler] Handler invoked for policy with id: ' +
                '9b6543c3-6d66-4cfb-a8fb-d780079278f6 and version: 1'
            Event   = 'AppDownload'; Detail = '1'
        }
        @{ Message = '[Win32App] lpExitCode 3010'; Event = 'AppInstallExit'; Detail = '3010' }
        @{
            Message = '[Win32App] lpExitCode is defined as Success'
            Event   = 'AppInstallOutcome'; Detail = 'Success'
        }
        @{
            Message = '[Win32App][ReportingManager] Sending status to company portal based on report: ' +
                '{"ApplicationId":"9b6543c3-6d66-4cfb-a8fb-d780079278f6","ResultantAppState":2,' +
                '"ReportingImpact":{}}'
            Event   = 'AppReport'; Detail = '2'
        }
        @{ Message = 'Prepare to run Powershell Script ..'; Event = 'ExecutorStart'; Detail = $null }
        @{ Message = 'Powershell exit code is 1'; Event = 'ExecutorExit'; Detail = '1' }
        @{ Message = 'write output done. output = issue found'; Event = 'ExecutorOutput'; Detail = 'issue found' }
        @{
            Message = "write output done. output = out-1`r`nout-2`r`n, error = boom`r`n"
            Event   = 'ExecutorOutput'; Detail = "out-1`r`nout-2 boom"
        }
        @{ Message = "write output done. output = `r`n, error = `r`n"; Event = 'ExecutorOutput'; Detail = $null }
        @{
            Message = "error from script =At C:\detect.ps1:60 char:35`r`n+ throw"
            Event   = 'ExecutorError'; Detail = "At C:\detect.ps1:60 char:35`r`n+ throw"
        }
        @{
            Message = 'Userless session, skip UserToken for device check-in'
            Event   = 'UserlessCheckin'; Detail = $null
        }
        @{
            Message = 'Finished ESP phase check before kicking off PowerShell script. ESP phase DeviceSetup'
            Event   = 'ScriptEspPhase'; Detail = 'DeviceSetup'
        }
        @{
            Message = '[Flighting] Key: RunNontrackedAppsCheckinImmediatelyAfterEsp, found value: True.'
            Event   = 'EspNontrackedCheckin'; Detail = 'True'
        }
        @{ Message = '[Win32App] The EspPhase: AccountSetup.'; Event = 'EspPhase'; Detail = 'AccountSetup' }
        @{
            Message = '[Win32App] The EspPhase: DeviceSetup in session'
            Event   = 'EspPhase'; Detail = 'DeviceSetup'
        }
        @{
            Message = '[Win32App][ESPAppLockInProcessor] Found 2 apps which need to be installed for current ' +
                'phase of ESP. AppIds: e693b92b-56c6-43a3-b4cf-e913c2999e22, 0597ac76-f189-401c-891b-92b372cf4d94'
            Event   = 'EspAppsSelected'; Detail = '2'
        }
        @{
            Message = '[Win32App][EspManager] In EspPhase: DeviceSetup. App ' +
                'e693b92b-56c6-43a3-b4cf-e913c2999e22 has been registered. App name: ISL-ESP-DEV-W32-BLOCK1'
            Event   = 'EspAppRegistered'; Detail = 'DeviceSetup ISL-ESP-DEV-W32-BLOCK1'
        }
        @{
            Message = '[Win32App][EspManager] In EspPhase: AccountSetup. App ' +
                '5f56607a-ea30-48ea-8816-df7c7321851e has been registered for user ' +
                'c3b8cf61-fac9-4450-943e-f6a246d9c7e6. App name: ISL-ESP-USR-W32-BLOCK'
            Event   = 'EspAppRegistered'; Detail = 'AccountSetup ISL-ESP-USR-W32-BLOCK'
        }
        @{
            Message = '[Win32App][EspManager] Updating ESP tracked install status from InProgress to ' +
                'Completed for application e693b92b-56c6-43a3-b4cf-e913c2999e22 with name: ISL-ESP-DEV-W32-BLOCK1.'
            Event   = 'EspAppState'; Detail = 'InProgress Completed'
        }
        @{
            Message = '[Win32App][EspHelper][CheckDeviceAndAccountSetupStateWithWmi] All apps completed for device'
            Event   = 'EspPhaseComplete'; Detail = 'device'
        }
        @{
            Message = '[Win32App][EspHelper][CheckDeviceAndAccountSetupStateWithWmi] all apps completed for user'
            Event   = 'EspPhaseComplete'; Detail = 'user'
        }
        @{
            Message = '[Win32App][EspHelper][OnEspRegistryValueChanged] ESP completed. Triggering immediate ' +
                'app workload check-in.'
            Event   = 'EspComplete'; Detail = $null
        }
        @{ Message = '[TamperProtection] Pass.'; Event = $null; Detail = $null }
        @{ Message = ''; Event = $null; Detail = $null }
    ) {
        $result = InModuleScope IntuneScriptLab -Parameters @{ Message = $Message } {
            Get-IslAgentLogEvent -Message $Message
        }
        $result.PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.AgentLogEvent'
        if ($null -eq $Event) { $result.Event | Should-BeNull } else { $result.Event | Should-Be $Event }
        if ($null -eq $Detail) { $result.Detail | Should-BeNull } else { $result.Detail | Should-Be $Detail }
    }

    It 'takes the first GUID in the message as the policy or app id, lower-cased' {
        $upper = '[HS] Runner: script BBF7E139-FE9D-4783-80DF-627B8E084059 will try to execute now.'
        $result = InModuleScope IntuneScriptLab -Parameters @{ Message = $upper } {
            Get-IslAgentLogEvent -Message $Message
        }
        $result.Id | Should-Be $script:Policy
        $none = InModuleScope IntuneScriptLab { Get-IslAgentLogEvent -Message 'Powershell exit code is 0' }
        $none.Id | Should-BeNull
    }

    It 'skips the empty GUID of a userless check-in when the policy id follows it' {
        $line = '[PowerShell] User Id = 00000000-0000-0000-0000-000000000000, Policy id = ' +
            'bbf7e139-fe9d-4783-80df-627b8e084059, policy result = Failed'
        $result = InModuleScope IntuneScriptLab -Parameters @{ Message = $line } {
            Get-IslAgentLogEvent -Message $Message
        }
        $result.Id | Should-Be $script:Policy
        $only = InModuleScope IntuneScriptLab {
            Get-IslAgentLogEvent -Message 'user 00000000-0000-0000-0000-000000000000 in session 0'
        }
        $only.Id | Should-Be '00000000-0000-0000-0000-000000000000'
    }

    It 'keeps the compiled table in the module scope with every event named once' {
        # The table is compiled on the first call, so make one: this test may run first
        $null = InModuleScope IntuneScriptLab { Get-IslAgentLogEvent -Message 'first check in on start' }
        $names = @(InModuleScope IntuneScriptLab { $script:IslAgentLogEvents | ForEach-Object { $_.Event } })
        $names.Count | Should-BeGreaterThan 25
        @($names | Sort-Object -Unique).Count | Should-Be $names.Count
        $names | Should-ContainCollection 'DetectionResult'
    }
}
