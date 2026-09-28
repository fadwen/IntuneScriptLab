#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The Graph pre-flight against a fake tenant: the Graph seam (Invoke-IslGraphRequest) is mocked
    with a small set of remediations, platform scripts and Win32 apps whose scripts carry known
    mistakes, and the findings are checked for the policy, the role, the settings the policy
    carries and the three deployment-level checks.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force

    function script:ConvertTo-Base64 {
        param([string]$Text, [switch]$Bom)
        $preamble = [System.Text.UTF8Encoding]::new([bool]$Bom).GetPreamble()
        [System.Convert]::ToBase64String($preamble + [System.Text.Encoding]::UTF8.GetBytes($Text))
    }
    # Detection: 'return' before 'exit 1' never triggers a remediation (IslExitCodeIssue)
    $script:DetectContent = ConvertTo-Base64 "if (Test-Path C:\x) { return 'ok' }`r`nexit 1"
    $script:RemediateContent = ConvertTo-Base64 "Remove-Item C:\x`r`nexit 0" -Bom
    $script:PlatformContent = ConvertTo-Base64 "Read-Host 'Continue?'`r`nexit 0" -Bom
    $script:CleanContent = ConvertTo-Base64 "Write-Output 'checked'`r`nexit 0" -Bom
    $deviceGroup = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = 'grp-devices' }
    # The same device group with an include filter whose only clause never matches a Windows device
    $filteredGroup = @{
        '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = 'grp-devices'
        deviceAndAppManagementAssignmentFilterId = 'flt-x64'
        deviceAndAppManagementAssignmentFilterType = 'include'
    }
    $script:Tenant = @{
        assignmentFilters = @{
            'flt-x64' = @{ id = 'flt-x64'; displayName = 'x64 only'; platform = 'windows10AndLater'
                rule = '(device.cpuArchitecture -eq "x64")' }
            'flt-lab' = @{ id = 'flt-lab'; displayName = 'Lab devices'; platform = 'windows10AndLater'
                rule = '(device.deviceName -startsWith "LAB-")' }
        }
        remediations = @(
            @{ id = 'rem-a'; displayName = 'Fix-Widget'; runAsAccount = 'user'; runAs32Bit = $true
                enforceSignatureCheck = $false; detectionScriptContent = $script:DetectContent
                remediationScriptContent = $script:RemediateContent
                assignments = @(@{ target = $filteredGroup }) }
            @{ id = 'rem-b'; displayName = 'Report-Only'; runAsAccount = 'system'; runAs32Bit = $false
                enforceSignatureCheck = $false; detectionScriptContent = $script:CleanContent
                remediationScriptContent = $null }
            # A run-once schedule that has passed, and one still to come
            @{ id = 'rem-c'; displayName = 'Old-Once'; runAsAccount = 'system'; runAs32Bit = $false
                enforceSignatureCheck = $false; detectionScriptContent = $script:CleanContent
                remediationScriptContent = $script:CleanContent
                assignments = @(@{ target = $deviceGroup; runSchedule = @{
                            '@odata.type' = '#microsoft.graph.deviceHealthScriptRunOnceSchedule'
                            useUtc = $true; date = '2026-01-15'; time = '08:30:00' } }) }
            @{ id = 'rem-d'; displayName = 'Next-Once'; runAsAccount = 'system'; runAs32Bit = $false
                enforceSignatureCheck = $false; detectionScriptContent = $script:CleanContent
                remediationScriptContent = $script:CleanContent
                assignments = @(@{ target = $deviceGroup; runSchedule = @{
                            '@odata.type' = '#microsoft.graph.deviceHealthScriptRunOnceSchedule'
                            useUtc = $true; date = '2099-01-15'; time = '08:30:00' } }) }
            # Only an exclusion
            @{ id = 'rem-e'; displayName = 'Excluded'; runAsAccount = 'system'; runAs32Bit = $false
                enforceSignatureCheck = $false; detectionScriptContent = $script:CleanContent
                remediationScriptContent = $script:CleanContent
                assignments = @(@{ target = @{
                            '@odata.type' = '#microsoft.graph.exclusionGroupAssignmentTarget'
                            groupId = 'grp-devices' } }) }
        )
        platformScripts = @(
            @{ id = 'ps-a'; displayName = 'Set-Wallpaper'; runAsAccount = 'user'; runAs32Bit = $false
                enforceSignatureCheck = $false; scriptContent = $script:PlatformContent }
        )
        apps = @(
            @{
                id = 'app-a'; displayName = 'Widget 2.0'
                installExperience = @{ runAsAccount = 'user' }
                detectionRules = @(
                    @{ '@odata.type' = '#microsoft.graph.win32LobAppPowerShellScriptDetection'
                        scriptContent = $script:CleanContent; enforceSignatureCheck = $true; runAs32Bit = $false }
                    @{ '@odata.type' = '#microsoft.graph.win32LobAppFileSystemDetection'
                        detectionType = 'doesNotExist'; path = 'C:\Legacy'; fileOrFolderName = 'old.exe' }
                    @{ '@odata.type' = '#microsoft.graph.win32LobAppFileSystemDetection'
                        detectionType = 'exists'; path = 'C:\Widget'; fileOrFolderName = 'widget.exe' }
                )
                requirementRules = @(
                    @{ '@odata.type' = '#microsoft.graph.win32LobAppPowerShellScriptRequirement'
                        scriptContent = $script:DetectContent; runAsAccount = 'system'; runAs32Bit = $true
                        enforceSignatureCheck = $false }
                    @{ '@odata.type' = '#microsoft.graph.win32LobAppRegistryRequirement' }
                )
                assignments = @(
                    @{ target = $deviceGroup }
                    @{ target = @{ '@odata.type' = '#microsoft.graph.allLicensedUsersAssignmentTarget'
                            deviceAndAppManagementAssignmentFilterId = 'flt-x64'
                            deviceAndAppManagementAssignmentFilterType = 'include' } }
                )
            }
            @{
                id = 'app-b'; displayName = 'Widget 1.0'
                installExperience = @{ runAsAccount = 'system' }
                detectionRules = @(
                    @{ '@odata.type' = '#microsoft.graph.win32LobAppRegistryDetection'; detectionType = 'exists' }
                )
                requirementRules = @()
                assignments = @(@{ target = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'
                            groupId = 'grp-devices'; deviceAndAppManagementAssignmentFilterId = 'flt-lab'
                            deviceAndAppManagementAssignmentFilterType = 'exclude' } })
            }
        )
        groups = @{
            'grp-devices' = @{ value = @(@{ '@odata.type' = '#microsoft.graph.device'; id = 'd1' }) }
            'grp-users'   = @{ value = @(@{ '@odata.type' = '#microsoft.graph.user'; id = 'u1' }) }
        }
    }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Test-IntuneDeployedScript' -Tag 'Unit', 'Public' {

    BeforeEach {
        # A mock body sees the test file's script scope, so the fake tenant is read from there
        Mock Invoke-IslGraphRequest -ModuleName IntuneScriptLab {
            $tenant = $script:Tenant
            $summary = {
                param($items)
                @($items | ForEach-Object { @{ id = $_.id; displayName = $_.displayName } })
            }
            switch -Regex ($Uri) {
                '^/beta/deviceManagement/deviceHealthScripts\?' { & $summary $tenant.remediations }
                '^/beta/deviceManagement/deviceHealthScripts/([^?]+)' {
                    $tenant.remediations | Where-Object id -eq $Matches[1]
                }
                '^/beta/deviceManagement/deviceManagementScripts\?' { & $summary $tenant.platformScripts }
                '^/beta/deviceManagement/deviceManagementScripts/([^?]+)' {
                    $tenant.platformScripts | Where-Object id -eq $Matches[1]
                }
                '^/beta/deviceManagement/assignmentFilters/([^?]+)' {
                    if (-not $tenant.assignmentFilters.ContainsKey($Matches[1])) { throw 'Resource not found' }
                    $tenant.assignmentFilters[$Matches[1]]
                }
                '^/beta/deviceAppManagement/mobileApps\?' { & $summary $tenant.apps }
                '^/beta/deviceAppManagement/mobileApps/([^?]+)' { $tenant.apps | Where-Object id -eq $Matches[1] }
                '^/v1.0/groups/([^/]+)/members' {
                    if (-not $tenant.groups.ContainsKey($Matches[1])) { throw 'Insufficient privileges' }
                    $tenant.groups[$Matches[1]]
                }
                default { throw "unexpected uri $Uri" }
            }
        }
    }

    Context 'Core Functionality' {
        It 'analyzes every deployed script with its policy settings and names the policy and role' {
            $findings = @(Test-IntuneDeployedScript)
            $findings.Count | Should-BeGreaterThan 4
            $findings[0].PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.DeploymentFinding'
            # Settings come from the policy, so the assumed-context note never appears
            $findings.RuleName | Should-NotContainCollection 'IslAssumedContext'
            $detection = @($findings | Where-Object {
                    $_.PolicyName -eq 'Fix-Widget' -and $_.Role -eq 'detection'
                })
            $detection.RuleName | Should-ContainCollection 'IslExitCodeIssue'
            $detection.ScriptType | Should-All { $_ -eq 'Detection' }
            $detection[0].Kind | Should-Be 'Remediation'
            $detection[0].PolicyId | Should-Be 'rem-a'
            $remediation = @($findings | Where-Object {
                    $_.PolicyName -eq 'Fix-Widget' -and $_.Role -eq 'remediation'
                })
            $remediation.ScriptType | Should-All { $_ -eq 'Remediation' }
            $platform = @($findings | Where-Object { $_.PolicyName -eq 'Set-Wallpaper' -and $_.Role -ne 'policy' })
            $platform.Role | Should-All { $_ -eq 'script' }
            $platform.RuleName | Should-ContainCollection 'IslInteractiveCall'
        }

        It 'passes the run-as account, bitness and signature check of each policy to the analysis' {
            Mock Test-IntuneScript -ModuleName IntuneScriptLab { }
            $null = Test-IntuneDeployedScript -Kind Remediation, Win32App
            Should-Invoke Test-IntuneScript -ModuleName IntuneScriptLab -ParameterFilter {
                $ScriptType -eq 'Detection' -and $Context -eq 'User' -and $Architecture -eq 'x86'
            } -Times 1 -Exactly
            Should-Invoke Test-IntuneScript -ModuleName IntuneScriptLab -ParameterFilter {
                $ScriptType -eq 'Win32Detection' -and $Context -eq 'System' -and $Architecture -eq 'x64' -and
                $EnforceSignatureCheck -eq $true
            } -Times 1 -Exactly
            Should-Invoke Test-IntuneScript -ModuleName IntuneScriptLab -ParameterFilter {
                $ScriptType -eq 'Win32Requirement' -and $Architecture -eq 'x86'
            } -Times 1 -Exactly
        }

        It 'flags a file doesNotExist detection rule (W32-FILE-NOTEXIST)' {
            $findings = @(Test-IntuneDeployedScript -Kind Win32App -IncludeRule IslDetectionRuleIssue)
            $findings.Count | Should-Be 1
            $findings[0].PolicyName | Should-Be 'Widget 2.0'
            $findings[0].Role | Should-Be 'policy'
            $findings[0].Severity | Should-Be 'Error'
            $findings[0].Message | Should-BeLikeString 'Detection rule 2 is a file rule*C:\Legacy\old.exe*'
        }

        It 'flags a user-context app assigned to a device group (W32-USER-INSTALL), once per app' {
            $findings = @(Test-IntuneDeployedScript -Kind Win32App -IncludeRule IslAssignmentIssue)
            $findings.Count | Should-Be 1
            $findings[0].PolicyName | Should-Be 'Widget 2.0'
            $findings[0].Severity | Should-Be 'Warning'
            $findings[0].Message | Should-BeLikeString '*grp-devices*'
            Should-Invoke Invoke-IslGraphRequest -ModuleName IntuneScriptLab -ParameterFilter {
                $Uri -like '/v1.0/groups/*'
            } -Times 1 -Exactly
        }

        It 'notes a remediation without a remediation script (REM-DETECTONLY)' {
            $findings = @(Test-IntuneDeployedScript -Kind Remediation -IncludeRule IslDetectOnly)
            $findings.Count | Should-Be 1
            $findings[0].PolicyName | Should-Be 'Report-Only'
            $findings[0].Severity | Should-Be 'Information'
        }

        It 'flags a filter clause no Windows device can match, reading each filter once (FLT-V25, FLT-E07)' {
            $findings = @(Test-IntuneDeployedScript -IncludeRule IslFilterIssue)
            $findings.Count | Should-Be 2
            @($findings.PolicyName | Sort-Object) | Should-BeCollection @('Fix-Widget', 'Widget 2.0')
            $findings.Severity | Should-All { $_ -eq 'Warning' }
            $findings.Role | Should-All { $_ -eq 'policy' }
            $expected = "Filter 'x64 only' (include): 'x64'*never matches*" +
                "Rule: (device.cpuArchitecture -eq `"x64`")"
            $findings[0].Message | Should-BeLikeString $expected
            Should-Invoke Invoke-IslGraphRequest -ModuleName IntuneScriptLab -ParameterFilter {
                $Uri -like '*/assignmentFilters/flt-x64'
            } -Times 1 -Exactly
            Should-Invoke Invoke-IslGraphRequest -ModuleName IntuneScriptLab -ParameterFilter {
                $Uri -like '*/assignmentFilters/flt-lab'
            } -Times 1 -Exactly
        }

        It 'skips the filter check after the tenant refuses to show a filter' {
            $filterRoute = { $Uri -like '*/assignmentFilters/*' }
            Mock Invoke-IslGraphRequest -ModuleName IntuneScriptLab -ParameterFilter $filterRoute {
                throw 'Insufficient privileges to complete the operation'
            }
            $warnings = @()
            $findings = @(Test-IntuneDeployedScript -WarningVariable warnings 3>$null)
            $findings.RuleName | Should-NotContainCollection 'IslFilterIssue'
            @($warnings).Count | Should-Be 1
            "$($warnings[0])" | Should-BeLikeString '*Assignment filters could not be read*'
        }

        It 'warns about a policy with no assignment or only exclusions (ASSIGN-NONE, ASSIGN-EXCLONLY)' {
            $findings = @(Test-IntuneDeployedScript -IncludeRule IslAssignmentIssue -MinimumSeverity Warning |
                Where-Object Message -like '*never runs anywhere*')
            @($findings.PolicyName | Sort-Object) |
                Should-BeCollection @('Excluded', 'Report-Only', 'Set-Wallpaper')
            ($findings | Where-Object PolicyName -eq 'Excluded').Message | Should-BeLikeString 'Only exclusion*'
            ($findings | Where-Object PolicyName -eq 'Report-Only').Message | Should-BeLikeString 'No assignment*'
            $findings.Role | Should-All { $_ -eq 'policy' }
        }

        It 'notes a run-once schedule whose time has passed, not one still to come (ASSIGN-PAST2)' {
            $findings = @(Test-IntuneDeployedScript -Kind Remediation -IncludeRule IslScheduleIssue)
            $findings.Count | Should-Be 1
            $findings[0].PolicyName | Should-Be 'Old-Once'
            $findings[0].Severity | Should-Be 'Information'
            $findings[0].Message | Should-BeLikeString 'Run-once schedule at 2026-01-15 08:30:00 (UTC) has passed*'
        }

        It 'notes a user-context script assigned to a device group (skipped on Entra registered devices)' {
            $testSplat = @{ Kind = 'Remediation', 'PlatformScript'; IncludeRule = 'IslAssignmentIssue' }
            $findings = @(Test-IntuneDeployedScript @testSplat | Where-Object Severity -eq 'Information')
            $findings.Count | Should-Be 1
            $findings[0].PolicyName | Should-Be 'Fix-Widget'
            $findings[0].Message | Should-BeLikeString 'User context, assigned to devices (grp-devices)*'
            $findings[0].Message | Should-BeLikeString '*Entra registered device downloads the policy and skips it'
        }

        It 'reports an unsigned Win32 detection script whose rule enforces the signature check' {
            $findings = @(Test-IntuneDeployedScript -Kind Win32App -Name 'Widget 2.0')
            $signature = @($findings | Where-Object {
                    $_.Role -eq 'detection' -and $_.RuleName -eq 'IslSignatureIssue'
                })
            $signature.Count | Should-Be 1
        }
    }

    Context 'Filters' {
        It 'reads only the kinds asked for' {
            @(Test-IntuneDeployedScript -Kind PlatformScript).PolicyName | Should-All { $_ -eq 'Set-Wallpaper' }
            Should-Invoke Invoke-IslGraphRequest -ModuleName IntuneScriptLab -ParameterFilter {
                $Uri -like '*mobileApps*' -or $Uri -like '*deviceHealthScripts*'
            } -Times 0 -Exactly
        }

        It 'reads only the policies whose name matches' {
            @(Test-IntuneDeployedScript -Name 'Fix-*').PolicyName | Should-All { $_ -eq 'Fix-Widget' }
            Should-Invoke Invoke-IslGraphRequest -ModuleName IntuneScriptLab -ParameterFilter {
                $Uri -like '*/deviceHealthScripts/rem-b*'
            } -Times 0 -Exactly
        }

        It 'reads a policy by id even when the name filter excludes it' {
            @(Test-IntuneDeployedScript -Name 'nothing' -Id 'app-b', 'rem-b').PolicyName |
                Sort-Object -Unique | Should-BeCollection @('Report-Only')
            Should-Invoke Invoke-IslGraphRequest -ModuleName IntuneScriptLab -ParameterFilter {
                $Uri -like '*/deviceHealthScripts/rem-a*'
            } -Times 0 -Exactly
            Should-Invoke Invoke-IslGraphRequest -ModuleName IntuneScriptLab -ParameterFilter {
                $Uri -like '*/mobileApps/app-b*'
            } -Times 1 -Exactly
        }

        It 'applies the rule and severity filters to script findings and policy checks alike' {
            $errors = @(Test-IntuneDeployedScript -MinimumSeverity Error)
            $errors.Severity | Should-All { $_ -eq 'Error' }
            $errors.RuleName | Should-ContainCollection 'IslDetectionRuleIssue'
            $errors.RuleName | Should-NotContainCollection 'IslDetectOnly'
            $errors.RuleName | Should-NotContainCollection 'IslFilterIssue'
            $without = @(Test-IntuneDeployedScript -ExcludeRule 'IslDetect*', 'IslAssignmentIssue')
            $without.RuleName | Should-NotContainCollection 'IslDetectOnly'
            $without.RuleName | Should-NotContainCollection 'IslDetectionRuleIssue'
            $without.RuleName | Should-NotContainCollection 'IslAssignmentIssue'
            $without.RuleName | Should-ContainCollection 'IslExitCodeIssue'
        }

        It 'skips the group lookup on request, and after the tenant refuses it' {
            $null = Test-IntuneDeployedScript -Kind Win32App -SkipGroupLookup
            Should-Invoke Invoke-IslGraphRequest -ModuleName IntuneScriptLab -ParameterFilter {
                $Uri -like '/v1.0/groups/*'
            } -Times 0 -Exactly
            $groupFilter = { $Uri -like '/v1.0/groups/*' }
            Mock Invoke-IslGraphRequest -ModuleName IntuneScriptLab -ParameterFilter $groupFilter {
                throw 'Insufficient privileges to complete the operation'
            }
            $warnings = @()
            $findings = @(Test-IntuneDeployedScript -Kind Win32App -WarningVariable warnings 3>$null)
            $findings.RuleName | Should-NotContainCollection 'IslAssignmentIssue'
            @($warnings).Count | Should-Be 1
            "$($warnings[0])" | Should-BeLikeString '*Group members could not be read*GroupMember.Read.All*'
        }
    }

    Context 'Error Handling' {
        It 'removes its temporary folder even when the analysis fails' {
            Mock Test-IntuneScript -ModuleName IntuneScriptLab { throw 'analysis broke' }
            $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'IntuneScriptLab'
            $listSplat = @{
                Path = $tempRoot; Filter = 'preflight-*'; Directory = $true; ErrorAction = 'SilentlyContinue'
            }
            $before = @(Get-ChildItem @listSplat).Count
            { Test-IntuneDeployedScript -Kind PlatformScript } | Should-Throw -ExceptionMessage '*analysis broke*'
            @(Get-ChildItem @listSplat).Count | Should-Be $before
        }
    }
}
