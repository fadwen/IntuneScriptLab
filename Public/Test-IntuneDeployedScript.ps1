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
    $null = New-Item -ItemType Directory -Path $workFolder -Force
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
        $displayName = "$($Policy.displayName)"
        # -Id alone selects by id: -Name's default of '*' only counts when -Name was given or -Id was not
        $byName = ($nameGiven -or -not $Id) -and @($Name | Where-Object { $displayName -like $_ }).Count -gt 0
        $byId = $Id -and "$($Policy.id)" -in $Id
        $byName -or $byId
    }

    function ConvertTo-DeploymentFinding {
        param([string]$PolicyKind, $Policy, [string]$Role, $Finding)
        [pscustomobject]@{
            PSTypeName = 'IntuneScriptLab.DeploymentFinding'
            Kind       = $PolicyKind
            PolicyName = "$($Policy.displayName)"
            PolicyId   = "$($Policy.id)"
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
        $safeName = [regex]::Replace("$($Policy.displayName)", '[^\w.-]', '_')
        $folder = Join-Path -Path $workFolder -ChildPath "$PolicyKind\$safeName-$($Policy.id)"
        $null = New-Item -ItemType Directory -Path $folder -Force
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
        Write-Verbose "$PolicyKind '$($Policy.displayName)' $Role as $ScriptType, $context, $architecture"
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
                $members = Invoke-IslGraphRequest -Uri "/v1.0/groups/$GroupId/members?`$select=id&`$top=20"
                $types = @($members.value | ForEach-Object { "$($_.'@odata.type')" })
                $others = @($types | Where-Object { $_ -ne '#microsoft.graph.device' })
                $isDeviceGroup = $types.Count -gt 0 -and $others.Count -eq 0
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
        foreach ($assignment in @($Policy.assignments)) {
            $target = $assignment.target
            $filterId = "$($target.deviceAndAppManagementAssignmentFilterId)"
            $filterType = "$($target.deviceAndAppManagementAssignmentFilterType)"
            if (-not $filterId -or $filterType -eq 'none') { continue }
            $filter = Get-AssignmentFilter -FilterId $filterId
            if (-not $filter) { continue }
            $label = "Filter '$($filter.displayName)' ($filterType)"
            $parsed = ConvertFrom-IslFilterRule -Rule "$($filter.rule)"
            if ($parsed.Error) {
                $unreadSplat = @{
                    PolicyKind = $PolicyKind; Policy = $Policy; Rule = 'IslFilterIssue'; Severity = 'Information'
                    Message    = "$label uses syntax this evaluator does not read ($($parsed.Error)): " +
                        "$($filter.rule)"
                    Evidence   = $filterEvidence
                }
                ConvertTo-PolicyFinding @unreadSplat
                continue
            }
            foreach ($warning in $parsed.Warnings) {
                $severity = if ($warning.Kind -eq 'NeverMatches') { 'Warning' } else { 'Information' }
                $issueSplat = @{
                    PolicyKind = $PolicyKind; Policy = $Policy; Rule = 'IslFilterIssue'; Severity = $severity
                    Message    = "${label}: $($warning.Message). Rule: $($filter.rule)"
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
        $assignments = @($Policy.assignments | Where-Object { $_ })
        $includes = @($assignments | Where-Object {
                "$($_.target.'@odata.type')" -ne '#microsoft.graph.exclusionGroupAssignmentTarget'
            })
        if ($includes.Count -eq 0) {
            $what = if ($assignments.Count -eq 0) { 'No assignment' } else { 'Only exclusion assignments' }
            $noneSplat = @{
                PolicyKind = $PolicyKind; Policy = $Policy; Rule = 'IslAssignmentIssue'; Severity = 'Warning'
                Message    = "${what}: no device resolves the policy, so it never runs anywhere"
                Evidence   = 'A remediation with no assignment and one with only an exclusion were absent ' +
                    'from every device''s resolved policies after an agent restart, while the same scripts ' +
                    'with an include assignment ran (ASSIGN-NONE, ASSIGN-EXCLONLY, ASSIGN-INEX)'
            }
            ConvertTo-PolicyFinding @noneSplat
        }
        foreach ($assignment in $includes) {
            $schedule = $assignment.runSchedule
            if ("$($schedule.'@odata.type')" -ne '#microsoft.graph.deviceHealthScriptRunOnceSchedule') { continue }
            $stamp = "$($schedule.date) $($schedule.time)"
            $at = [datetime]::MinValue
            if (-not [datetime]::TryParse($stamp, [cultureinfo]::InvariantCulture, 'None', [ref]$at)) { continue }
            $now = if ([bool]$schedule.useUtc) { [datetime]::UtcNow } else { [datetime]::Now }
            if ($at -ge $now) { continue }
            $zone = if ([bool]$schedule.useUtc) { 'UTC' } else { 'device local time' }
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
            $target = $assignment.target
            $type = "$($target.'@odata.type')"
            if ($type -eq '#microsoft.graph.allDevicesAssignmentTarget') { 'all devices'; continue }
            if ($type -ne '#microsoft.graph.groupAssignmentTarget') { continue }
            if (Test-DeviceGroup -GroupId "$($target.groupId)") { "$($target.groupId)" }
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
                $policy = Invoke-IslGraphRequest -Uri "$remediations/$($summary.id)?`$expand=assignments"
                $policySettings = @{
                    RunAsAccount = $policy.runAsAccount; RunAs32Bit = $policy.runAs32Bit
                    EnforceSignatureCheck = $policy.enforceSignatureCheck
                }
                $detectSplat = @{
                    PolicyKind = 'Remediation'; Policy = $policy; Role = 'detection'; ScriptType = 'Detection'
                    Content    = $policy.detectionScriptContent
                }
                Test-PolicyScript @detectSplat @policySettings
                if ($policy.remediationScriptContent) {
                    $remediateSplat = @{
                        PolicyKind = 'Remediation'; Policy = $policy; Role = 'remediation'
                        ScriptType = 'Remediation'; Content = $policy.remediationScriptContent
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
                Test-Assignment -PolicyKind 'Remediation' -Policy $policy -RunAsAccount $policy.runAsAccount
                Test-AssignmentFilter -PolicyKind 'Remediation' -Policy $policy
            }
        }

        if ('PlatformScript' -in $Kind) {
            $scripts = '/beta/deviceManagement/deviceManagementScripts'
            foreach ($summary in (Get-WantedPolicy -Uri "$scripts`?`$select=id,displayName")) {
                $policy = Invoke-IslGraphRequest -Uri "$scripts/$($summary.id)?`$expand=assignments"
                $scriptSplat = @{
                    PolicyKind = 'PlatformScript'; Policy = $policy; Role = 'script'; ScriptType = 'PlatformScript'
                    Content    = $policy.scriptContent; RunAsAccount = $policy.runAsAccount
                    RunAs32Bit = $policy.runAs32Bit; EnforceSignatureCheck = $policy.enforceSignatureCheck
                }
                Test-PolicyScript @scriptSplat
                Test-Assignment -PolicyKind 'PlatformScript' -Policy $policy -RunAsAccount $policy.runAsAccount
                Test-AssignmentFilter -PolicyKind 'PlatformScript' -Policy $policy
            }
        }

        if ('Win32App' -in $Kind) {
            $apps = '/beta/deviceAppManagement/mobileApps'
            $listUri = "$apps`?`$filter=isof('microsoft.graph.win32LobApp')&`$select=id,displayName"
            foreach ($summary in (Get-WantedPolicy -Uri $listUri)) {
                $app = Invoke-IslGraphRequest -Uri "$apps/$($summary.id)?`$expand=assignments"
                $ruleIndex = 0
                foreach ($rule in @($app.detectionRules)) {
                    $ruleIndex++
                    $ruleType = "$($rule.'@odata.type')"
                    if ($ruleType -eq '#microsoft.graph.win32LobAppPowerShellScriptDetection') {
                        $detectSplat = @{
                            PolicyKind = 'Win32App'; Policy = $app; Role = 'detection'
                            ScriptType = 'Win32Detection'; Content = $rule.scriptContent
                            RunAsAccount = 'system'; RunAs32Bit = $rule.runAs32Bit
                            EnforceSignatureCheck = $rule.enforceSignatureCheck
                        }
                        Test-PolicyScript @detectSplat
                    }
                    elseif ($ruleType -eq '#microsoft.graph.win32LobAppFileSystemDetection' -and
                        "$($rule.detectionType)" -eq 'doesNotExist') {
                        $ruleSplat = @{
                            PolicyKind = 'Win32App'; Policy = $app; Rule = 'IslDetectionRuleIssue'
                            Severity   = 'Error'
                            Message    = "Detection rule $ruleIndex is a file rule with detectionType " +
                                "doesNotExist ($($rule.path)\$($rule.fileOrFolderName)): the agent does " +
                                'not evaluate it. Use a registry doesNotExist rule or a script'
                            Evidence   = 'File doesNotExist: on a missing file the app was not detected ' +
                                'and the install ran; on a present file the detection ended "Invalid ' +
                                'detection rule or unable to parse detection rule" 0x87D30004 ' +
                                '(W32-FILE-NOTEXIST, W32-FILE-NOTEXIST-PRESENT)'
                        }
                        ConvertTo-PolicyFinding @ruleSplat
                    }
                }
                foreach ($rule in @($app.requirementRules)) {
                    if ("$($rule.'@odata.type')" -ne '#microsoft.graph.win32LobAppPowerShellScriptRequirement') {
                        continue
                    }
                    $requirementSplat = @{
                        PolicyKind = 'Win32App'; Policy = $app; Role = 'requirement'
                        ScriptType = 'Win32Requirement'; Content = $rule.scriptContent
                        RunAsAccount = $rule.runAsAccount; RunAs32Bit = $rule.runAs32Bit
                        EnforceSignatureCheck = $rule.enforceSignatureCheck
                    }
                    Test-PolicyScript @requirementSplat
                }
                if ("$($app.installExperience.runAsAccount)" -eq 'user') {
                    $deviceGroups = foreach ($assignment in @($app.assignments)) {
                        $target = $assignment.target
                        if ("$($target.'@odata.type')" -ne '#microsoft.graph.groupAssignmentTarget') { continue }
                        if (Test-DeviceGroup -GroupId "$($target.groupId)") { "$($target.groupId)" }
                    }
                    if ($deviceGroups) {
                        $assignmentSplat = @{
                            PolicyKind = 'Win32App'; Policy = $app; Rule = 'IslAssignmentIssue'
                            Severity   = 'Warning'
                            Message    = 'Install behavior User, assigned to a group of devices ' +
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
        Remove-Item -LiteralPath $workFolder -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Verbose "Completed $($MyInvocation.MyCommand.Name)"
}
