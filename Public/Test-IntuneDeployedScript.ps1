function Test-IntuneDeployedScript {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Analyzes the scripts a tenant has deployed, with the settings each policy actually carries.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.DeploymentFinding')]
    param(
        [ValidateSet('Remediation', 'PlatformScript', 'Win32App')]
        [string[]]$Kind = @('Remediation', 'PlatformScript', 'Win32App'),

        [SupportsWildcards()]
        [string[]]$Name = @('*'),

        [string[]]$Id,

        [string[]]$IncludeRule,

        [string[]]$ExcludeRule,

        [ValidateSet('Information', 'Warning', 'Error')]
        [string]$MinimumSeverity = 'Information',

        [switch]$SkipGroupLookup,

        # A settings file path or hashtable for the analysis (the tenant's scripts have no folder
        # of their own to carry one)
        $Settings
    )
    Write-Verbose "Starting $($MyInvocation.MyCommand.Name) for $($PSBoundParameters.Keys -join ', ')"
    # Captured here: inside the nested functions $PSBoundParameters is their own, not this command's
    $nameGiven = $PSBoundParameters.ContainsKey('Name')
    $settingsGiven = $PSBoundParameters.ContainsKey('Settings')

    $severityRank = @{ Information = 0; Warning = 1; Error = 2 }
    $workName = "IntuneScriptLab\preflight-$([guid]::NewGuid().ToString('N'))"
    $workFolder = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath $workName
    # The work folder is this command's own: it reads the tenant and changes nothing, so a
    # caller's -WhatIf or -Confirm preference has no say in it
    $null = New-Item -ItemType Directory -Path $workFolder -Force @script:IslInternal
    # Mutable state the nested functions share (an assignment inside them would make a local copy)
    $groupState = @{ Cache = @{}; Blocked = $false }
    $filterState = @{ Cache = @{}; Blocked = $false }
    $filterEvidence = 'validateFilter accepted (device.cpuArchitecture -eq "x64") and (device.deviceTrustType ' +
        '-eq "Microsoft Entra joined") and the filter evaluator matched no device with either: Windows ' +
        'reports amd64 and "Azure AD joined" (FLT-V25, FLT-E07, FLT-V27, FLT-F01)'

    function Test-Selected {
        param([string]$Rule)
        if ($IncludeRule -and -not ($IncludeRule | Where-Object { $Rule -like $_ })) { return $false }
        if ($ExcludeRule -and ($ExcludeRule | Where-Object { $Rule -like $_ })) { return $false }
        $true
    }

    function Test-Wanted {
        param($Policy)
        $displayName = "$(Get-IslPropertyValue -InputObject $Policy -Name 'displayName')"
        $policyId = "$(Get-IslPropertyValue -InputObject $Policy -Name 'id')"
        # -Id alone selects by id: -Name's default of '*' only counts when -Name was given or -Id was not
        $byName = ($nameGiven -or -not $Id) -and @($Name | Where-Object { $displayName -like $_ }).Count -gt 0
        $byId = $Id -and $policyId -in $Id
        $byName -or $byId
    }

    function ConvertTo-DeploymentFinding {
        param([string]$PolicyKind, $Policy, [string]$Role, $Finding)
        [pscustomobject]@{
            PSTypeName = 'IntuneScriptLab.DeploymentFinding'
            Kind       = $PolicyKind
            PolicyName = "$(Get-IslPropertyValue -InputObject $Policy -Name 'displayName')"
            PolicyId   = "$(Get-IslPropertyValue -InputObject $Policy -Name 'id')"
            Role       = $Role
            RuleName   = $Finding.RuleName
            Severity   = $Finding.Severity
            Message    = $Finding.Message
            ScriptType = $Finding.ScriptType
            Line       = $Finding.Line
            Column     = $Finding.Column
            Text       = $Finding.Text
            Evidence   = $Finding.Evidence
        }
    }

    function ConvertTo-PolicyFinding {
        param([string]$PolicyKind, $Policy, [string]$Rule, [string]$Severity, [string]$Message, [string]$Evidence)
        if (-not (Test-Selected -Rule $Rule) -or $severityRank[$Severity] -lt $severityRank[$MinimumSeverity]) {
            return
        }
        $finding = [pscustomobject]@{
            RuleName = $Rule; Severity = $Severity; Message = $Message; ScriptType = ''
            Line = 0; Column = 0; Text = ''; Evidence = $Evidence
        }
        ConvertTo-DeploymentFinding -PolicyKind $PolicyKind -Policy $Policy -Role 'policy' -Finding $finding
    }

    # Runs the script rules on one base64 script with the policy's own settings
    function Test-PolicyScript {
        param(
            [string]$PolicyKind, $Policy, [string]$Role, [string]$Content, [string]$ScriptType,
            $RunAsAccount, $RunAs32Bit, $EnforceSignatureCheck
        )
        if (-not $Content) { return }
        $policyName = "$(Get-IslPropertyValue -InputObject $Policy -Name 'displayName')"
        $policyId = "$(Get-IslPropertyValue -InputObject $Policy -Name 'id')"
        $safeName = [regex]::Replace($policyName, '[^\w.-]', '_')
        $folder = Join-Path -Path $workFolder -ChildPath "$PolicyKind\$safeName-$policyId"
        $null = New-Item -ItemType Directory -Path $folder -Force @script:IslInternal
        $file = Join-Path -Path $folder -ChildPath "$Role.ps1"
        # Byte for byte: the encoding rule needs to see the BOM, or its absence, as the tenant stores it
        [System.IO.File]::WriteAllBytes($file, [System.Convert]::FromBase64String($Content))
        $context = if ("$RunAsAccount" -eq 'user') { 'User' } else { 'System' }
        $architecture = if ([bool]$RunAs32Bit) { 'x86' } else { 'x64' }
        $testSplat = @{
            Path                  = $file
            ScriptType            = $ScriptType
            Context               = $context
            Architecture          = $architecture
            EnforceSignatureCheck = [bool]$EnforceSignatureCheck
            MinimumSeverity       = $MinimumSeverity
        }
        if ($settingsGiven) { $testSplat.Settings = $Settings }
        if ($IncludeRule) { $testSplat.IncludeRule = $IncludeRule }
        if ($ExcludeRule) { $testSplat.ExcludeRule = $ExcludeRule }
        Write-Verbose "$PolicyKind '$policyName' $Role as $ScriptType, $context, $architecture"
        foreach ($finding in (Test-IntuneScript @testSplat)) {
            ConvertTo-DeploymentFinding -PolicyKind $PolicyKind -Policy $Policy -Role $Role -Finding $finding
        }
    }

    function Test-DeviceGroup {
        param([string]$GroupId)
        if ($groupState.Cache.ContainsKey($GroupId)) { return $groupState.Cache[$GroupId] }
        $isDeviceGroup = $false
        if (-not $SkipGroupLookup -and -not $groupState.Blocked) {
            try {
                # Two counts, every member and the devices among them, rather than a page of
                # members: a page of 20 decided for the whole group, and a mixed group whose first
                # 20 members were devices passed as a device group. $count needs the eventual
                # consistency header and answers with the number as text (dev tenant, 2026-10-06)
                $countSplat = @{ Headers = @{ ConsistencyLevel = 'eventual' } }
                $total = [int](Invoke-IslGraphRequest -Uri "/v1.0/groups/$GroupId/members/`$count" @countSplat)
                $deviceUri = "/v1.0/groups/$GroupId/members/microsoft.graph.device/`$count"
                $devices = [int](Invoke-IslGraphRequest -Uri $deviceUri @countSplat)
                $isDeviceGroup = $total -gt 0 -and $devices -eq $total
            }
            catch {
                $groupState.Blocked = $true
                Write-Warning ("Group members could not be read ($($_.Exception.Message)); the assignment " +
                    'check is skipped. GroupMember.Read.All allows it, -SkipGroupLookup silences this')
            }
        }
        $groupState.Cache[$GroupId] = $isDeviceGroup
        $isDeviceGroup
    }

    function Get-AssignmentFilter {
        param([string]$FilterId)
        if ($filterState.Cache.ContainsKey($FilterId)) { return $filterState.Cache[$FilterId] }
        $filter = $null
        if (-not $filterState.Blocked) {
            try {
                $filter = Invoke-IslGraphRequest -Uri "/beta/deviceManagement/assignmentFilters/$FilterId"
            }
            catch {
                $filterState.Blocked = $true
                Write-Warning ("Assignment filters could not be read ($($_.Exception.Message)); the filter " +
                    'check is skipped. DeviceManagementConfiguration.Read.All allows it')
            }
        }
        $filterState.Cache[$FilterId] = $filter
        $filter
    }

    # The filters on a policy's assignments: a rule the parser refuses is noted, a clause no Windows
    # device can match is a warning (the assignment silently reaches nobody, or everybody)
    function Test-AssignmentFilter {
        param([string]$PolicyKind, $Policy)
        foreach ($assignment in @(Get-IslPropertyValue -InputObject $Policy -Name 'assignments')) {
            # An assignment without a filter carries neither key, or a type of none
            $target = Get-IslPropertyValue -InputObject $assignment -Name 'target'
            $filterId = Get-IslPropertyValue -InputObject $target -Name 'deviceAndAppManagementAssignmentFilterId'
            $filterTypeName = 'deviceAndAppManagementAssignmentFilterType'
            $filterType = "$(Get-IslPropertyValue -InputObject $target -Name $filterTypeName)"
            if (-not $filterId -or $filterType -eq 'none') { continue }
            $filter = Get-AssignmentFilter -FilterId $filterId
            if (-not $filter) { continue }
            $filterRule = "$(Get-IslPropertyValue -InputObject $filter -Name 'rule')"
            $label = "Filter '$(Get-IslPropertyValue -InputObject $filter -Name 'displayName')' ($filterType)"
            $parsed = ConvertFrom-IslFilterRule -Rule $filterRule
            if ($parsed.Error) {
                $unreadSplat = @{
                    PolicyKind = $PolicyKind; Policy = $Policy; Rule = 'IslFilterIssue'; Severity = 'Information'
                    Message    = "$label uses syntax this evaluator does not read ($($parsed.Error)): $filterRule"
                    Evidence   = $filterEvidence
                }
                ConvertTo-PolicyFinding @unreadSplat
                continue
            }
            $mode = if ($filterType -eq 'exclude') { 'Exclude' } else { 'Include' }
            foreach ($warning in $parsed.Warnings) {
                $severity = if ($warning.Kind -eq 'NeverMatches') { 'Warning' } else { 'Information' }
                $message = Get-IslFilterWarningMessage -Warning $warning -Mode $mode
                $issueSplat = @{
                    PolicyKind = $PolicyKind; Policy = $Policy; Rule = 'IslFilterIssue'; Severity = $severity
                    Message    = "${label}: $message. Rule: $filterRule"
                    Evidence   = $filterEvidence
                }
                ConvertTo-PolicyFinding @issueSplat
            }
        }
    }

    # The assignments themselves (round 9, Findings "Assignment sanity"): none or exclusions only
    # mean the policy is never resolved by any device; a run-once schedule whose time has passed
    # runs once at the fetch on a device that has not run it; a user-context script assigned to a
    # device group is skipped on Entra registered devices
    function Test-Assignment {
        param([string]$PolicyKind, $Policy, $RunAsAccount)
        $assignments = @(Get-IslPropertyValue -InputObject $Policy -Name 'assignments' | Where-Object { $_ })
        $exclusionType = '#microsoft.graph.exclusionGroupAssignmentTarget'
        $includes = @($assignments | Where-Object {
                $target = Get-IslPropertyValue -InputObject $_ -Name 'target'
                "$(Get-IslPropertyValue -InputObject $target -Name '@odata.type')" -ne $exclusionType
            })
        if ($includes.Count -eq 0) {
            $what = if ($assignments.Count -eq 0) { 'No assignment' } else { 'Only exclusion assignments' }
            $noneSplat = @{
                PolicyKind = $PolicyKind; Policy = $Policy; Rule = 'IslAssignmentIssue'; Severity = 'Warning'
                Message    = "${what}: no device resolves the policy, so it never runs anywhere"
                Evidence   = 'A remediation with no assignment and one with only an exclusion were absent ' +
                    'from every device''s resolved policies after an agent restart, while the same scripts ' +
                    'with an include assignment ran (ASSIGN-NONE, ASSIGN-EXCLONLY)'
            }
            ConvertTo-PolicyFinding @noneSplat
        }
        foreach ($assignment in $includes) {
            # Only a remediation's assignment has a schedule, and only a run-once one has a date
            $schedule = Get-IslPropertyValue -InputObject $assignment -Name 'runSchedule'
            $scheduleType = "$(Get-IslPropertyValue -InputObject $schedule -Name '@odata.type')"
            if ($scheduleType -ne '#microsoft.graph.deviceHealthScriptRunOnceSchedule') { continue }
            $scheduleDate = Get-IslPropertyValue -InputObject $schedule -Name 'date'
            $scheduleTime = Get-IslPropertyValue -InputObject $schedule -Name 'time'
            $useUtc = [bool](Get-IslPropertyValue -InputObject $schedule -Name 'useUtc')
            $stamp = "$scheduleDate $scheduleTime"
            $at = [datetime]::MinValue
            if (-not [datetime]::TryParse($stamp, [cultureinfo]::InvariantCulture, 'None', [ref]$at)) { continue }
            $now = if ($useUtc) { [datetime]::UtcNow } else { [datetime]::Now }
            if ($at -ge $now) { continue }
            $zone = if ($useUtc) { 'UTC' } else { 'device local time' }
            $when = $at.ToString('yyyy-MM-dd HH:mm:ss')
            $pastSplat = @{
                PolicyKind = $PolicyKind; Policy = $Policy; Rule = 'IslScheduleIssue'; Severity = 'Information'
                Message    = "Run-once schedule at $when ($zone) has passed: a device that already ran it " +
                    'will not again, and one that fetches the policy now runs it once at the fetch'
                Evidence   = 'A run-once remediation dated two hours earlier ran once about six minutes ' +
                    'after a device fetched it, then never again; a device whose clock had not reached ' +
                    'the time waited for it (ASSIGN-PAST2, ASSIGN-PAST, REM-RUNONCE)'
            }
            ConvertTo-PolicyFinding @pastSplat
        }
        if ("$RunAsAccount" -ne 'user') { return }
        $deviceGroups = foreach ($assignment in $includes) {
            $target = Get-IslPropertyValue -InputObject $assignment -Name 'target'
            $type = "$(Get-IslPropertyValue -InputObject $target -Name '@odata.type')"
            if ($type -eq '#microsoft.graph.allDevicesAssignmentTarget') { 'all devices'; continue }
            if ($type -ne '#microsoft.graph.groupAssignmentTarget') { continue }
            $groupId = "$(Get-IslPropertyValue -InputObject $target -Name 'groupId')"
            if (Test-DeviceGroup -GroupId $groupId) { $groupId }
        }
        if ($deviceGroups) {
            $userSplat = @{
                PolicyKind = $PolicyKind; Policy = $Policy; Rule = 'IslAssignmentIssue'; Severity = 'Information'
                Message    = "User context, assigned to devices ($($deviceGroups -join ', ')): runs as the " +
                    'signed-in user on Entra joined and hybrid joined devices only; an Entra registered ' +
                    'device downloads the policy and skips it'
                Evidence   = 'On the Entra registered device the agent logged "This is not AADJ/HAADJ device, ' +
                    'skip user context" for every user-context remediation and platform script and never ran ' +
                    'them; the joined device ran them as the signed-in user (rounds 1-3, "Join type")'
            }
            ConvertTo-PolicyFinding @userSplat
        }
    }

    function Get-WantedPolicy {
        param([string]$Uri)
        @(Invoke-IslGraphRequest -Uri $Uri -All | Where-Object { Test-Wanted -Policy $_ })
    }

    try {
        if ('Remediation' -in $Kind) {
            $remediations = '/beta/deviceManagement/deviceHealthScripts'
            foreach ($summary in (Get-WantedPolicy -Uri "$remediations`?`$select=id,displayName")) {
                $summaryId = Get-IslPropertyValue -InputObject $summary -Name 'id'
                $policy = Invoke-IslGraphRequest -Uri "$remediations/$summaryId`?`$expand=assignments"
                $runAsAccount = Get-IslPropertyValue -InputObject $policy -Name 'runAsAccount'
                $policySettings = @{
                    RunAsAccount = $runAsAccount
                    RunAs32Bit = Get-IslPropertyValue -InputObject $policy -Name 'runAs32Bit'
                    EnforceSignatureCheck = Get-IslPropertyValue -InputObject $policy -Name 'enforceSignatureCheck'
                }
                $detectSplat = @{
                    PolicyKind = 'Remediation'
                    Policy = $policy
                    Role = 'detection'
                    ScriptType = 'Detection'
                    Content = Get-IslPropertyValue -InputObject $policy -Name 'detectionScriptContent'
                }
                Test-PolicyScript @detectSplat @policySettings
                $remediationContent = Get-IslPropertyValue -InputObject $policy -Name 'remediationScriptContent'
                if ($remediationContent) {
                    $remediateSplat = @{
                        PolicyKind = 'Remediation'; Policy = $policy; Role = 'remediation'
                        ScriptType = 'Remediation'; Content = $remediationContent
                    }
                    Test-PolicyScript @remediateSplat @policySettings
                }
                else {
                    $noteSplat = @{
                        PolicyKind = 'Remediation'; Policy = $policy; Rule = 'IslDetectOnly'
                        Severity   = 'Information'
                        Message    = 'No remediation script: the detection runs alone on its schedule and the ' +
                            'portal shows the issue without fixing it'
                        Evidence   = 'A remediation created without remediationScriptContent ran its detection ' +
                            'alone every cycle; Graph reports remediationState skipped (REM-DETECTONLY)'
                    }
                    ConvertTo-PolicyFinding @noteSplat
                }
                Test-Assignment -PolicyKind 'Remediation' -Policy $policy -RunAsAccount $runAsAccount
                Test-AssignmentFilter -PolicyKind 'Remediation' -Policy $policy
            }
        }

        if ('PlatformScript' -in $Kind) {
            $scripts = '/beta/deviceManagement/deviceManagementScripts'
            foreach ($summary in (Get-WantedPolicy -Uri "$scripts`?`$select=id,displayName")) {
                $summaryId = Get-IslPropertyValue -InputObject $summary -Name 'id'
                $policy = Invoke-IslGraphRequest -Uri "$scripts/$summaryId`?`$expand=assignments"
                $runAsAccount = Get-IslPropertyValue -InputObject $policy -Name 'runAsAccount'
                $scriptSplat = @{
                    PolicyKind = 'PlatformScript'
                    Policy = $policy
                    Role = 'script'
                    ScriptType = 'PlatformScript'
                    Content = Get-IslPropertyValue -InputObject $policy -Name 'scriptContent'
                    RunAsAccount = $runAsAccount
                    RunAs32Bit = Get-IslPropertyValue -InputObject $policy -Name 'runAs32Bit'
                    EnforceSignatureCheck = Get-IslPropertyValue -InputObject $policy -Name 'enforceSignatureCheck'
                }
                Test-PolicyScript @scriptSplat
                Test-Assignment -PolicyKind 'PlatformScript' -Policy $policy -RunAsAccount $runAsAccount
                Test-AssignmentFilter -PolicyKind 'PlatformScript' -Policy $policy
            }
        }

        if ('Win32App' -in $Kind) {
            $apps = '/beta/deviceAppManagement/mobileApps'
            $listUri = "$apps`?`$filter=isof('microsoft.graph.win32LobApp')&`$select=id,displayName"
            foreach ($summary in (Get-WantedPolicy -Uri $listUri)) {
                $summaryId = Get-IslPropertyValue -InputObject $summary -Name 'id'
                $app = Invoke-IslGraphRequest -Uri "$apps/$summaryId`?`$expand=assignments"
                $ruleIndex = 0
                foreach ($rule in @(Get-IslPropertyValue -InputObject $app -Name 'detectionRules')) {
                    $ruleIndex++
                    # Each kind of rule has its own members: a script rule has no detectionType,
                    # a file rule no scriptContent
                    $ruleType = "$(Get-IslPropertyValue -InputObject $rule -Name '@odata.type')"
                    $detectionType = "$(Get-IslPropertyValue -InputObject $rule -Name 'detectionType')"
                    if ($ruleType -eq '#microsoft.graph.win32LobAppPowerShellScriptDetection') {
                        $signatureCheck = Get-IslPropertyValue -InputObject $rule -Name 'enforceSignatureCheck'
                        $detectSplat = @{
                            PolicyKind = 'Win32App'
                            Policy = $app
                            Role = 'detection'
                            ScriptType = 'Win32Detection'
                            Content = Get-IslPropertyValue -InputObject $rule -Name 'scriptContent'
                            RunAsAccount = 'system'
                            RunAs32Bit = Get-IslPropertyValue -InputObject $rule -Name 'runAs32Bit'
                            EnforceSignatureCheck = $signatureCheck
                        }
                        Test-PolicyScript @detectSplat
                    }
                    elseif ($ruleType -eq '#microsoft.graph.win32LobAppFileSystemDetection' -and
                        $detectionType -eq 'doesNotExist') {
                        $rulePath = Get-IslPropertyValue -InputObject $rule -Name 'path'
                        $ruleFile = Get-IslPropertyValue -InputObject $rule -Name 'fileOrFolderName'
                        $ruleSplat = @{
                            PolicyKind = 'Win32App'; Policy = $app; Rule = 'IslDetectionRuleIssue'
                            Severity   = 'Error'
                            Message    = "Detection rule $ruleIndex is a file rule with detectionType " +
                                "doesNotExist ($rulePath\$ruleFile): the agent does " +
                                'not evaluate it. Use a registry doesNotExist rule or a script'
                            Evidence   = 'File doesNotExist: on a missing file the app was not detected ' +
                                'and the install ran; on a present file the detection ended "Invalid ' +
                                'detection rule or unable to parse detection rule" 0x87D30004 ' +
                                '(W32-FILE-NOTEXIST, W32-FILE-NOTEXIST-FALSE)'
                        }
                        ConvertTo-PolicyFinding @ruleSplat
                    }
                }
                foreach ($rule in @(Get-IslPropertyValue -InputObject $app -Name 'requirementRules')) {
                    $ruleType = "$(Get-IslPropertyValue -InputObject $rule -Name '@odata.type')"
                    if ($ruleType -ne '#microsoft.graph.win32LobAppPowerShellScriptRequirement') {
                        continue
                    }
                    $signatureCheck = Get-IslPropertyValue -InputObject $rule -Name 'enforceSignatureCheck'
                    $requirementSplat = @{
                        PolicyKind = 'Win32App'
                        Policy = $app
                        Role = 'requirement'
                        ScriptType = 'Win32Requirement'
                        Content = Get-IslPropertyValue -InputObject $rule -Name 'scriptContent'
                        RunAsAccount = Get-IslPropertyValue -InputObject $rule -Name 'runAsAccount'
                        RunAs32Bit = Get-IslPropertyValue -InputObject $rule -Name 'runAs32Bit'
                        EnforceSignatureCheck = $signatureCheck
                    }
                    Test-PolicyScript @requirementSplat
                }
                $installExperience = Get-IslPropertyValue -InputObject $app -Name 'installExperience'
                $installContext = "$(Get-IslPropertyValue -InputObject $installExperience -Name 'runAsAccount')"
                if ($installContext -eq 'user') {
                    $appAssignments = @(Get-IslPropertyValue -InputObject $app -Name 'assignments')
                    $deviceGroups = foreach ($assignment in $appAssignments) {
                        $target = Get-IslPropertyValue -InputObject $assignment -Name 'target'
                        $type = "$(Get-IslPropertyValue -InputObject $target -Name '@odata.type')"
                        if ($type -eq '#microsoft.graph.allDevicesAssignmentTarget') { 'all devices'; continue }
                        if ($type -ne '#microsoft.graph.groupAssignmentTarget') { continue }
                        $groupId = "$(Get-IslPropertyValue -InputObject $target -Name 'groupId')"
                        if (Test-DeviceGroup -GroupId $groupId) { $groupId }
                    }
                    if ($deviceGroups) {
                        $assignmentSplat = @{
                            PolicyKind = 'Win32App'; Policy = $app; Rule = 'IslAssignmentIssue'
                            Severity   = 'Warning'
                            Message    = 'Install behavior User, assigned to devices ' +
                                "($($deviceGroups -join ', ')): the app is never installed there. Assign " +
                                'it to users'
                            Evidence   = 'A user-context app assigned to a device group was never installed ' +
                                'on either join type: "user install context and this is a userless ' +
                                'check-in", Not applicable, Applicability 1011 (W32-USER-INSTALL)'
                        }
                        ConvertTo-PolicyFinding @assignmentSplat
                    }
                }
                # Install context is not a script context: the user-context note does not apply to apps
                Test-Assignment -PolicyKind 'Win32App' -Policy $app -RunAsAccount 'system'
                Test-AssignmentFilter -PolicyKind 'Win32App' -Policy $app
            }
        }
    }
    finally {
        Remove-Item -LiteralPath $workFolder -Recurse -Force -ErrorAction SilentlyContinue @script:IslInternal
    }
    Write-Verbose "Completed $($MyInvocation.MyCommand.Name)"
}
