function Test-IntuneDeployedScript {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Analyzes a tenant's deployed scripts with the settings each policy carries.
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
        [object]$Settings
    )
    # SEC-16: checked here, not with [ValidateLength()], which would also refuse $null
    try {
        Assert-IslTextLength -Name 'Name' -Value $Name
        Assert-IslTextLength -Name 'Id' -Value $Id
        Assert-IslTextLength -Name 'IncludeRule' -Value $IncludeRule
        Assert-IslTextLength -Name 'ExcludeRule' -Value $ExcludeRule
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
    Write-Verbose "Starting $($MyInvocation.MyCommand.Name) for $($PSBoundParameters.Keys -join ', ')"
    # Which policies of each list to read; -Id alone selects by id, so whether -Name was given counts
    $wanted = @{ Name = $Name; Id = $Id; NameGiven = $PSBoundParameters.ContainsKey('Name') }

    $workParent = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'IntuneScriptLab'
    $workFolder = Join-Path -Path $workParent -ChildPath "preflight-$([guid]::NewGuid().ToString('N'))"
    # The work folder is this command's own: it reads the tenant and changes nothing, so a
    # caller's -WhatIf or -Confirm preference has no say in it
    $null = New-Item -ItemType Directory -Path $workFolder -Force @script:IslInternal
    # Each group and each filter is asked for once in the run; a lookup that is refused is skipped
    # for the rest of it
    $groupState = @{ Cache = @{}; Blocked = $false }
    $filterState = @{ Cache = @{}; Blocked = $false }
    # What the caller asked of the findings, which every check of a policy applies
    $ruleOptions = @{ IncludeRule = $IncludeRule; ExcludeRule = $ExcludeRule; MinimumSeverity = $MinimumSeverity }
    $scriptOptions = $ruleOptions + @{ WorkFolder = $workFolder }
    if ($PSBoundParameters.ContainsKey('Settings')) { $scriptOptions.Settings = $Settings }
    $assignmentOptions = $ruleOptions + @{ GroupState = $groupState; SkipGroupLookup = $SkipGroupLookup }
    $filterOptions = $ruleOptions + @{ FilterState = $filterState }
    try {
        if ('Remediation' -in $Kind) {
            $remediations = '/beta/deviceManagement/deviceHealthScripts'
            try {
                $summaries = @(Get-IslSelectedPolicy -Uri "$remediations`?`$select=id,displayName" @wanted)
            } catch {
                $PSCmdlet.ThrowTerminatingError($_)
            }
            foreach ($summary in $summaries) {
                # A read that fails ends the command. What one policy gives is written after its try, so
                # that an error of a command further down the pipeline is not caught here
                $policyOutput = try {
                    $summaryId = Get-IslPropertyValue -InputObject $summary -Name 'id'
                    $policy = Invoke-IslGraphRequest -Uri "$remediations/$summaryId`?`$expand=assignments"
                    $runAsAccount = Get-IslPropertyValue -InputObject $policy -Name 'runAsAccount'
                    $enforceSignature = Get-IslPropertyValue -InputObject $policy -Name 'enforceSignatureCheck'
                    $policySettings = @{
                        RunAsAccount = $runAsAccount
                        RunAs32Bit = Get-IslPropertyValue -InputObject $policy -Name 'runAs32Bit'
                        EnforceSignatureCheck = $enforceSignature
                    }
                    $detectSplat = @{
                        PolicyKind = 'Remediation'
                        Policy = $policy
                        Role = 'detection'
                        ScriptType = 'Detection'
                        Content = Get-IslPropertyValue -InputObject $policy -Name 'detectionScriptContent'
                    }
                    Test-IslPolicyScript @detectSplat @policySettings @scriptOptions
                    $contentName = 'remediationScriptContent'
                    $remediationContent = Get-IslPropertyValue -InputObject $policy -Name $contentName
                    if ($remediationContent) {
                        $remediateSplat = @{
                            PolicyKind = 'Remediation'; Policy = $policy; Role = 'remediation'
                            ScriptType = 'Remediation'; Content = $remediationContent
                        }
                        Test-IslPolicyScript @remediateSplat @policySettings @scriptOptions
                    } else {
                        $detectOnlyEvidence = ('A remediation created without remediationScriptContent ran ' +
                            'its detection alone every cycle; Graph reports remediationState skipped ' +
                            '(REM-DETECTONLY)')
                        $noteSplat = @{
                            PolicyKind = 'Remediation'; Policy = $policy; Rule = 'IslDetectOnly'
                            Severity = 'Information'
                            Message = 'No remediation script: the detection runs alone on its schedule and ' +
                            'the portal shows the issue without fixing it'
                            Evidence = $detectOnlyEvidence
                        }
                        ConvertTo-IslPolicyFinding @noteSplat @ruleOptions
                    }
                    $checkSplat = @{ PolicyKind = 'Remediation'; Policy = $policy; RunAsAccount = $runAsAccount }
                    Test-IslPolicyAssignment @checkSplat @assignmentOptions
                    Test-IslAssignmentFilter -PolicyKind 'Remediation' -Policy $policy @filterOptions
                } catch {
                    $PSCmdlet.ThrowTerminatingError($_)
                }
                $policyOutput
            }
        }

        if ('PlatformScript' -in $Kind) {
            $scripts = '/beta/deviceManagement/deviceManagementScripts'
            try {
                $summaries = @(Get-IslSelectedPolicy -Uri "$scripts`?`$select=id,displayName" @wanted)
            } catch {
                $PSCmdlet.ThrowTerminatingError($_)
            }
            foreach ($summary in $summaries) {
                $policyOutput = try {
                    $summaryId = Get-IslPropertyValue -InputObject $summary -Name 'id'
                    $policy = Invoke-IslGraphRequest -Uri "$scripts/$summaryId`?`$expand=assignments"
                    $runAsAccount = Get-IslPropertyValue -InputObject $policy -Name 'runAsAccount'
                    $enforceSignature = Get-IslPropertyValue -InputObject $policy -Name 'enforceSignatureCheck'
                    $scriptSplat = @{
                        PolicyKind = 'PlatformScript'
                        Policy = $policy
                        Role = 'script'
                        ScriptType = 'PlatformScript'
                        Content = Get-IslPropertyValue -InputObject $policy -Name 'scriptContent'
                        RunAsAccount = $runAsAccount
                        RunAs32Bit = Get-IslPropertyValue -InputObject $policy -Name 'runAs32Bit'
                        EnforceSignatureCheck = $enforceSignature
                    }
                    Test-IslPolicyScript @scriptSplat @scriptOptions
                    $checkSplat = @{
                        PolicyKind = 'PlatformScript'; Policy = $policy; RunAsAccount = $runAsAccount
                    }
                    Test-IslPolicyAssignment @checkSplat @assignmentOptions
                    Test-IslAssignmentFilter -PolicyKind 'PlatformScript' -Policy $policy @filterOptions
                } catch {
                    $PSCmdlet.ThrowTerminatingError($_)
                }
                $policyOutput
            }
        }

        if ('Win32App' -in $Kind) {
            $apps = '/beta/deviceAppManagement/mobileApps'
            $listUri = "$apps`?`$filter=isof('microsoft.graph.win32LobApp')&`$select=id,displayName"
            try {
                $summaries = @(Get-IslSelectedPolicy -Uri $listUri @wanted)
            } catch {
                $PSCmdlet.ThrowTerminatingError($_)
            }
            foreach ($summary in $summaries) {
                $policyOutput = try {
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
                            Test-IslPolicyScript @detectSplat @scriptOptions
                        } elseif ($ruleType -eq '#microsoft.graph.win32LobAppFileSystemDetection' -and
                            $detectionType -eq 'doesNotExist') {
                            $rulePath = Get-IslPropertyValue -InputObject $rule -Name 'path'
                            $ruleFile = Get-IslPropertyValue -InputObject $rule -Name 'fileOrFolderName'
                            $ruleSplat = @{
                                PolicyKind = 'Win32App'; Policy = $app; Rule = 'IslDetectionRuleIssue'
                                Severity = 'Error'
                                Message = "Detection rule $ruleIndex is a file rule with detectionType " +
                                "doesNotExist ($rulePath\$ruleFile): the agent does " +
                                'not evaluate it. Use a registry doesNotExist rule or a script'
                                Evidence = 'File doesNotExist: on a missing file the app was not detected ' +
                                'and the install ran; on a present file the detection ended "Invalid ' +
                                'detection rule or unable to parse detection rule" 0x87D30004 ' +
                                '(W32-FILE-NOTEXIST, W32-FILE-NOTEXIST-FALSE)'
                            }
                            ConvertTo-IslPolicyFinding @ruleSplat @ruleOptions
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
                        Test-IslPolicyScript @requirementSplat @scriptOptions
                    }
                    $installExperience = Get-IslPropertyValue -InputObject $app -Name 'installExperience'
                    $installAccount = Get-IslPropertyValue -InputObject $installExperience -Name 'runAsAccount'
                    $installContext = "$installAccount"
                    if ($installContext -eq 'user') {
                        $appAssignments = @(Get-IslPropertyValue -InputObject $app -Name 'assignments')
                        $deviceGroups = foreach ($assignment in $appAssignments) {
                            $target = Get-IslPropertyValue -InputObject $assignment -Name 'target'
                            $type = "$(Get-IslPropertyValue -InputObject $target -Name '@odata.type')"
                            if ($type -eq '#microsoft.graph.allDevicesAssignmentTarget') {
                                'all devices'
                                continue
                            }
                            if ($type -ne '#microsoft.graph.groupAssignmentTarget') { continue }
                            $groupId = "$(Get-IslPropertyValue -InputObject $target -Name 'groupId')"
                            $deviceGroupSplat = @{
                                GroupId = $groupId; State = $groupState; SkipGroupLookup = $SkipGroupLookup
                            }
                            if (Test-IslDeviceGroup @deviceGroupSplat) { $groupId }
                        }
                        if ($deviceGroups) {
                            $assignmentSplat = @{
                                PolicyKind = 'Win32App'; Policy = $app; Rule = 'IslAssignmentIssue'
                                Severity = 'Warning'
                                Message = 'Install behavior User, assigned to devices ' +
                                "($($deviceGroups -join ', ')): the app is never installed there. Assign " +
                                'it to users'
                                Evidence = 'A user-context app assigned to a device group was never installed ' +
                                'on either join type: "user install context and this is a userless ' +
                                'check-in", Not applicable, Applicability 1011 (W32-USER-INSTALL)'
                            }
                            ConvertTo-IslPolicyFinding @assignmentSplat @ruleOptions
                        }
                    }
                    # Install context is not a script context: the user-context note does not apply to apps
                    $checkSplat = @{ PolicyKind = 'Win32App'; Policy = $app; RunAsAccount = 'system' }
                    Test-IslPolicyAssignment @checkSplat @assignmentOptions
                    Test-IslAssignmentFilter -PolicyKind 'Win32App' -Policy $app @filterOptions
                } catch {
                    $PSCmdlet.ThrowTerminatingError($_)
                }
                $policyOutput
            }
        }
    } finally {
        Remove-Item -LiteralPath $workFolder -Recurse -Force -ErrorAction SilentlyContinue @script:IslInternal
    }
    Write-Verbose "Completed $($MyInvocation.MyCommand.Name)"
}
