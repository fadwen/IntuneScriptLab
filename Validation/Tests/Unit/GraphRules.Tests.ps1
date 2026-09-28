#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The Graph objects the validation kit builds from Experiments.psd1: one win32LobApp*Rule per rule
    spec, the full rule set per Win32 experiment, and the remediation run schedule. GraphRules.ps1 has
    no #Requires lines and no Graph calls, so it is dot-sourced as it is.
#>

BeforeAll {
    $script:KitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:KitRoot 'GraphRules.ps1')
    # Stands in for ConvertTo-ScriptContent: records what it was asked to encode
    $script:Encode = { param($Body, $Bom) "B64[$Body|bom=$Bom]" }
}

Describe 'ConvertTo-Win32AppRule' -Tag 'Unit', 'Validation' {

    Context 'File rules' {
        It 'builds a win32LobAppFileSystemRule with the operator and value given' {
            $rule = ConvertTo-Win32AppRule -RuleType detection -Rule @{
                Type = 'File'; Path = 'C:\Fixtures'; FileOrFolderName = 'v.exe'
                OperationType = 'version'; Operator = 'greaterThanOrEqual'; ComparisonValue = '9.0'
            }
            $rule.'@odata.type' | Should-Be '#microsoft.graph.win32LobAppFileSystemRule'
            $rule.ruleType | Should-Be 'detection'
            $rule.path | Should-Be 'C:\Fixtures'
            $rule.fileOrFolderName | Should-Be 'v.exe'
            $rule.operationType | Should-Be 'version'
            $rule.operator | Should-Be 'greaterThanOrEqual'
            $rule.comparisonValue | Should-Be '9.0'
            $rule.check32BitOn64System | Should-BeFalse
        }

        It 'defaults an exists rule to operator notConfigured and a null value, like the portal' {
            $rule = ConvertTo-Win32AppRule -RuleType requirement -Rule @{
                Type = 'File'; Path = '%ProgramFiles%\App'; FileOrFolderName = 'a.txt'; OperationType = 'exists'
                Check32BitOn64System = $true
            }
            $rule.ruleType | Should-Be 'requirement'
            $rule.operator | Should-Be 'notConfigured'
            $rule.comparisonValue | Should-BeNull
            $rule.check32BitOn64System | Should-BeTrue
        }

        It 'refuses a file rule without <Missing>' -ForEach @(
            @{ Missing = 'Path' }
            @{ Missing = 'FileOrFolderName' }
            @{ Missing = 'OperationType' }
        ) {
            $spec = @{ Type = 'File'; Path = 'C:\x'; FileOrFolderName = 'a'; OperationType = 'exists' }
            $spec.Remove($Missing)
            { ConvertTo-Win32AppRule -RuleType detection -Rule $spec } |
                Should-Throw -ExceptionMessage "*needs $Missing*"
        }
    }

    Context 'Registry rules' {
        It 'builds a win32LobAppRegistryRule and passes the 32-bit view flag through' {
            $rule = ConvertTo-Win32AppRule -RuleType detection -Rule @{
                Type = 'Registry'; KeyPath = 'HKEY_LOCAL_MACHINE\SOFTWARE\X'; ValueName = 'View'
                OperationType = 'string'; Operator = 'equal'; ComparisonValue = '32'; Check32BitOn64System = $true
            }
            $rule.'@odata.type' | Should-Be '#microsoft.graph.win32LobAppRegistryRule'
            $rule.keyPath | Should-Be 'HKEY_LOCAL_MACHINE\SOFTWARE\X'
            $rule.valueName | Should-Be 'View'
            $rule.operationType | Should-Be 'string'
            $rule.comparisonValue | Should-Be '32'
            $rule.check32BitOn64System | Should-BeTrue
        }

        It 'sends a null value name for a key-level rule' {
            $rule = ConvertTo-Win32AppRule -RuleType detection -Rule @{
                Type = 'Registry'; KeyPath = 'HKEY_LOCAL_MACHINE\SOFTWARE\X'; OperationType = 'doesNotExist'
            }
            $rule.valueName | Should-BeNull
            $rule.operationType | Should-Be 'doesNotExist'
            $rule.operator | Should-Be 'notConfigured'
        }

        It 'stringifies a numeric comparison value, as Graph expects a string' {
            $rule = ConvertTo-Win32AppRule -RuleType detection -Rule @{
                Type = 'Registry'; KeyPath = 'HKEY_LOCAL_MACHINE\SOFTWARE\X'; ValueName = 'Build'
                OperationType = 'integer'; Operator = 'greaterThan'; ComparisonValue = 40
            }
            $rule.comparisonValue | Should-HaveType ([string])
            $rule.comparisonValue | Should-Be '40'
        }
    }

    Context 'Product code rules' {
        It 'builds a win32LobAppProductCodeRule without a version check by default' {
            $rule = ConvertTo-Win32AppRule -RuleType detection -Rule @{
                Type = 'ProductCode'; ProductCode = '{FBE4D84C-C935-4F54-B96F-49316CEB5149}'
            }
            $rule.'@odata.type' | Should-Be '#microsoft.graph.win32LobAppProductCodeRule'
            $rule.productCode | Should-Be '{FBE4D84C-C935-4F54-B96F-49316CEB5149}'
            $rule.productVersionOperator | Should-Be 'notConfigured'
            $rule.productVersion | Should-BeNull
        }

        It 'carries a version operator and value when given' {
            $rule = ConvertTo-Win32AppRule -RuleType detection -Rule @{
                Type = 'ProductCode'; ProductCode = '{1}'; ProductVersionOperator = 'greaterThan'
                ProductVersion = '2.0'
            }
            $rule.productVersionOperator | Should-Be 'greaterThan'
            $rule.productVersion | Should-Be '2.0'
        }

        It 'refuses to be a requirement rule, as Graph does' {
            { ConvertTo-Win32AppRule -RuleType requirement -Rule @{ Type = 'ProductCode'; ProductCode = '{1}' } } |
                Should-Throw -ExceptionMessage '*only be a detection rule*'
        }
    }

    Context 'Script rules' {
        It 'builds a detection script rule with only the detection properties' {
            $rule = ConvertTo-Win32AppRule -RuleType detection -Rule @{
                Type = 'Script'; ScriptContent = 'AAA='; RunAs32Bit = $true; EnforceSignatureCheck = $true
            }
            $rule.'@odata.type' | Should-Be '#microsoft.graph.win32LobAppPowerShellScriptRule'
            $rule.scriptContent | Should-Be 'AAA='
            $rule.runAs32Bit | Should-BeTrue
            $rule.enforceSignatureCheck | Should-BeTrue
            # The portal sends none of these for a detection rule
            $rule.ContainsKey('displayName') | Should-BeFalse
            $rule.ContainsKey('runAsAccount') | Should-BeFalse
            $rule.ContainsKey('operationType') | Should-BeFalse
        }

        It 'defaults a requirement script rule to SYSTEM, string equal ok' {
            $rule = ConvertTo-Win32AppRule -RuleType requirement -Rule @{ Type = 'Script'; ScriptContent = 'AAA=' }
            $rule.displayName | Should-Be 'ISL requirement probe'
            $rule.runAsAccount | Should-Be 'system'
            $rule.operationType | Should-Be 'string'
            $rule.operator | Should-Be 'equal'
            $rule.comparisonValue | Should-Be 'ok'
            $rule.enforceSignatureCheck | Should-BeFalse
        }

        It 'lets a requirement override the context and the comparison' {
            $rule = ConvertTo-Win32AppRule -RuleType requirement -Rule @{
                Type = 'Script'; ScriptContent = 'AAA='; RunAsAccount = 'user'; OperationType = 'version'
                Operator = 'greaterThanOrEqual'; ComparisonValue = '2.9.0'
            }
            $rule.runAsAccount | Should-Be 'user'
            $rule.operationType | Should-Be 'version'
            $rule.operator | Should-Be 'greaterThanOrEqual'
            $rule.comparisonValue | Should-Be '2.9.0'
        }

        It 'refuses a script rule with no content' {
            { ConvertTo-Win32AppRule -RuleType detection -Rule @{ Type = 'Script' } } |
                Should-Throw -ExceptionMessage '*ScriptContent*'
        }
    }

    Context 'Error Handling' {
        It 'refuses an unknown rule type' {
            { ConvertTo-Win32AppRule -RuleType detection -Rule @{ Type = 'Wmi' } } |
                Should-Throw -ExceptionMessage "*Unknown rule type 'Wmi'*"
        }
    }
}

Describe 'Get-Win32AppRuleSet' -Tag 'Unit', 'Validation' {

    It 'turns the legacy Detection and Requirement keys into script rules through the encoder' {
        $experiment = @{
            Name        = 'W32-REQ-BASE'
            Detection   = 'exit 1'
            Bom         = $true
            RunAs32Bit  = $true
            Requirement = @{ Script = 'Write-Output ok'; RunAsAccount = 'user' }
        }
        $rules = @(Get-Win32AppRuleSet -Experiment $experiment -Encode $script:Encode)
        $rules.Count | Should-Be 2
        $rules[0].ruleType | Should-Be 'detection'
        $rules[0].scriptContent | Should-Be 'B64[exit 1|bom=True]'
        $rules[0].runAs32Bit | Should-BeTrue
        $rules[1].ruleType | Should-Be 'requirement'
        $rules[1].scriptContent | Should-Be 'B64[Write-Output ok|bom=False]'
        $rules[1].runAsAccount | Should-Be 'user'
        $rules[1].comparisonValue | Should-Be 'ok'
    }

    It 'passes the detection script enforceSignatureCheck flag through' {
        $rules = @(Get-Win32AppRuleSet -Encode $script:Encode -Experiment @{
                Name = 'W32-DET-SIGCHECK'; Detection = 'exit 0'; EnforceSignatureCheck = $true
            })
        $rules[0].enforceSignatureCheck | Should-BeTrue
    }

    It 'lists the detection script first, then DetectionRules, then RequirementRules' {
        $experiment = @{
            Name             = 'W32-MIX'
            Detection        = 'exit 1'
            DetectionRules   = @(
                @{ Type = 'File'; Path = 'C:\F'; FileOrFolderName = 'a'; OperationType = 'exists' }
                @{ Type = 'ProductCode'; ProductCode = '{1}' }
            )
            RequirementRules = @(
                @{ Type = 'Registry'; KeyPath = 'HKEY_LOCAL_MACHINE\SOFTWARE\X'; OperationType = 'exists' }
            )
        }
        $rules = @(Get-Win32AppRuleSet -Experiment $experiment -Encode $script:Encode)
        $rules.'@odata.type' | Should-BeCollection @(
            '#microsoft.graph.win32LobAppPowerShellScriptRule'
            '#microsoft.graph.win32LobAppFileSystemRule'
            '#microsoft.graph.win32LobAppProductCodeRule'
            '#microsoft.graph.win32LobAppRegistryRule'
        )
        $rules.ruleType | Should-BeCollection @('detection', 'detection', 'detection', 'requirement')
    }

    It 'accepts an experiment with rules and no detection script' {
        $rules = @(Get-Win32AppRuleSet -Encode $script:Encode -Experiment @{
                Name = 'W32-FILE-EXISTS'
                DetectionRules = @(@{
                        Type = 'File'; Path = 'C:\F'; FileOrFolderName = 'a'; OperationType = 'exists'
                    })
            })
        $rules.Count | Should-Be 1
        $rules[0].'@odata.type' | Should-Be '#microsoft.graph.win32LobAppFileSystemRule'
    }

    It 'encodes a script spec inside DetectionRules too' {
        $rules = @(Get-Win32AppRuleSet -Encode $script:Encode -Experiment @{
                Name = 'W32-TWO-SCRIPTS'
                DetectionRules = @(@{ Type = 'Script'; Script = 'exit 0'; Bom = $true })
            })
        $rules[0].scriptContent | Should-Be 'B64[exit 0|bom=True]'
    }

    It 'does not modify the experiment it was given' {
        $spec = @{ Type = 'Script'; Script = 'exit 0' }
        $experiment = @{ Name = 'W32-X'; DetectionRules = @($spec) }
        $null = Get-Win32AppRuleSet -Experiment $experiment -Encode $script:Encode
        $spec.ContainsKey('ScriptContent') | Should-BeFalse
    }

    It 'refuses an experiment with only requirement rules, as Graph would' {
        { Get-Win32AppRuleSet -Encode $script:Encode -Experiment @{
                Name = 'W32-NODETECT'
                RequirementRules = @(@{
                        Type = 'File'; Path = 'C:\F'; FileOrFolderName = 'a'; OperationType = 'exists'
                    })
            } } | Should-Throw -ExceptionMessage '*W32-NODETECT has no detection rule*'
    }
}

Describe 'ConvertTo-RemediationSchedule' -Tag 'Unit', 'Validation' {

    It 'is hourly, interval 1, when the experiment has no Schedule' {
        $schedule = ConvertTo-RemediationSchedule
        $schedule.'@odata.type' | Should-Be '#microsoft.graph.deviceHealthScriptHourlySchedule'
        $schedule.interval | Should-Be 1
    }

    It 'honours an hourly interval' {
        (ConvertTo-RemediationSchedule -Schedule @{ Interval = 4 }).interval | Should-Be 4
    }

    It 'schedules a run-once at the reference time plus the delay, in UTC' {
        $now = [datetime]::new(2026, 9, 24, 23, 50, 0, [DateTimeKind]::Utc)
        $schedule = ConvertTo-RemediationSchedule -Schedule @{ Type = 'RunOnce'; DelayMinutes = 20 } -Now $now
        $schedule.'@odata.type' | Should-Be '#microsoft.graph.deviceHealthScriptRunOnceSchedule'
        $schedule.useUtc | Should-BeTrue
        $schedule.interval | Should-Be 1
        # Crosses midnight, so the date must move too
        $schedule.date | Should-Be '2026-09-25'
        $schedule.time | Should-Be '00:10:00'
    }

    It 'defaults the run-once delay to ten minutes' {
        $now = [datetime]::new(2026, 1, 1, 12, 0, 0, [DateTimeKind]::Utc)
        (ConvertTo-RemediationSchedule -Schedule @{ Type = 'RunOnce' } -Now $now).time | Should-Be '12:10:00'
    }

    It 'converts a local reference time to UTC' {
        $local = [datetime]::new(2026, 1, 1, 12, 0, 0, [DateTimeKind]::Local)
        $schedule = ConvertTo-RemediationSchedule -Schedule @{ Type = 'RunOnce'; DelayMinutes = 0 } -Now $local
        $schedule.time | Should-Be $local.ToUniversalTime().ToString('HH:mm:ss')
    }

    It 'builds a daily schedule with the time of day only' {
        $now = [datetime]::new(2026, 1, 1, 12, 0, 0, [DateTimeKind]::Utc)
        $daily = @{ Type = 'Daily'; DelayMinutes = 5; Interval = 2 }
        $schedule = ConvertTo-RemediationSchedule -Schedule $daily -Now $now
        $schedule.'@odata.type' | Should-Be '#microsoft.graph.deviceHealthScriptDailySchedule'
        $schedule.interval | Should-Be 2
        $schedule.time | Should-Be '12:05:00'
        $schedule.ContainsKey('date') | Should-BeFalse
    }
}
