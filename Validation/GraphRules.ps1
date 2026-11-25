# Graph objects built from Experiments.psd1 entries: Win32 detection/requirement rules and remediation
# run schedules. Dot-sourced by Invoke-ValidationRound.ps1 and kept apart from it so the assembly can be
# unit-tested without a Graph connection or the driver's #Requires lines.
# The specs are hashtables that Experiments.psd1 writes, so their keys are read with an index: a key
# that a spec leaves out is $null that way, where member access is an error under strict mode.


function ConvertTo-Win32AppRule {
    <#
    .SYNOPSIS
        Converts an experiment rule spec into the win32LobApp*Rule object for Graph.

    .DESCRIPTION
        Turns one experiment rule spec into the win32LobApp*Rule object the Graph API expects.

        Spec keys by Type:
          File         Path, FileOrFolderName, OperationType (exists, doesNotExist, version, sizeInMB,
                       modifiedDate, createdDate), Operator, ComparisonValue, Check32BitOn64System
          Registry     KeyPath, ValueName, OperationType (exists, doesNotExist, string, integer, version),
                       Operator, ComparisonValue, Check32BitOn64System
          ProductCode  ProductCode, ProductVersionOperator, ProductVersion; detection only
          Script       ScriptContent (base64, probe already prepended), RunAs32Bit, EnforceSignatureCheck;
                       a requirement also takes RunAsAccount, OperationType, Operator, ComparisonValue
        Operator defaults to notConfigured and ComparisonValue to null, which is what the portal sends for
        an exists rule.

        A spec that lacks a key its type needs, a product code rule asked for as a requirement, and an
        unknown Type are terminating errors.

    .PARAMETER Rule
        The spec hashtable from Experiments.psd1.

    .PARAMETER RuleType
        detection or requirement.

    .EXAMPLE
        ConvertTo-Win32AppRule -RuleType detection -Rule @{
            Type = 'File'; Path = 'C:\Temp'; FileOrFolderName = 'a.txt'; OperationType = 'exists'
        }

        A win32LobAppFileSystemRule that detects C:\Temp\a.txt, with operator notConfigured.

    .INPUTS
        None.

    .OUTPUTS
        System.Collections.Hashtable. The rule as Graph takes it.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Rule,

        [Parameter(Mandatory)]
        [ValidateSet('detection', 'requirement')]
        [string]$RuleType
    )

    $invalidArgument = [System.Management.Automation.ErrorCategory]::InvalidArgument
    $operator = if ($Rule['Operator']) { $Rule['Operator'] } else { 'notConfigured' }
    $value = if ($null -ne $Rule['ComparisonValue']) { [string]$Rule['ComparisonValue'] } else { $null }

    switch ($Rule['Type']) {
        'File' {
            foreach ($key in 'Path', 'FileOrFolderName', 'OperationType') {
                if (-not $Rule[$key]) {
                    $exception = [System.ArgumentException]::new("File rule needs $key")
                    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                        $exception, 'Win32RuleFieldMissing', $invalidArgument, $Rule)
                    $PSCmdlet.ThrowTerminatingError($errorRecord)
                }
            }
            @{
                '@odata.type' = '#microsoft.graph.win32LobAppFileSystemRule'
                ruleType = $RuleType
                path = $Rule['Path']
                fileOrFolderName = $Rule['FileOrFolderName']
                check32BitOn64System = [bool]$Rule['Check32BitOn64System']
                operationType = $Rule['OperationType']
                operator = $operator
                comparisonValue = $value
            }
        }
        'Registry' {
            foreach ($key in 'KeyPath', 'OperationType') {
                if (-not $Rule[$key]) {
                    $exception = [System.ArgumentException]::new("Registry rule needs $key")
                    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                        $exception, 'Win32RuleFieldMissing', $invalidArgument, $Rule)
                    $PSCmdlet.ThrowTerminatingError($errorRecord)
                }
            }
            @{
                '@odata.type' = '#microsoft.graph.win32LobAppRegistryRule'
                ruleType = $RuleType
                check32BitOn64System = [bool]$Rule['Check32BitOn64System']
                keyPath = $Rule['KeyPath']
                valueName = if ($Rule['ValueName']) { $Rule['ValueName'] } else { $null }
                operationType = $Rule['OperationType']
                operator = $operator
                comparisonValue = $value
            }
        }
        'ProductCode' {
            if ($RuleType -ne 'detection') {
                $exception = [System.ArgumentException]::new('A product code rule can only be a detection rule')
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception, 'ProductCodeRuleNotDetection', $invalidArgument, $Rule)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
            if (-not $Rule['ProductCode']) {
                $exception = [System.ArgumentException]::new('ProductCode rule needs ProductCode')
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception, 'Win32RuleFieldMissing', $invalidArgument, $Rule)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
            $versionOperator = if ($Rule['ProductVersionOperator']) {
                $Rule['ProductVersionOperator']
            } else {
                'notConfigured'
            }
            @{
                '@odata.type' = '#microsoft.graph.win32LobAppProductCodeRule'
                ruleType = $RuleType
                productCode = $Rule['ProductCode']
                productVersionOperator = $versionOperator
                productVersion = if ($Rule['ProductVersion']) { [string]$Rule['ProductVersion'] } else { $null }
            }
        }
        'Script' {
            if (-not $Rule['ScriptContent']) {
                $exception = [System.ArgumentException]::new('Script rule needs ScriptContent (base64)')
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception, 'Win32RuleFieldMissing', $invalidArgument, $Rule)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
            $graphRule = @{
                '@odata.type' = '#microsoft.graph.win32LobAppPowerShellScriptRule'
                ruleType = $RuleType
                enforceSignatureCheck = [bool]$Rule['EnforceSignatureCheck']
                runAs32Bit = [bool]$Rule['RunAs32Bit']
                scriptContent = $Rule['ScriptContent']
            }
            if ($RuleType -eq 'requirement') {
                # Defaults: SYSTEM, "output equals ok"
                $graphRule['displayName'] = if ($Rule['DisplayName']) {
                    $Rule['DisplayName']
                } else {
                    'ISL requirement probe'
                }
                $graphRule['runAsAccount'] = if ($Rule['RunAsAccount']) { $Rule['RunAsAccount'] } else { 'system' }
                $graphRule['operationType'] = if ($Rule['OperationType']) {
                    $Rule['OperationType']
                } else {
                    'string'
                }
                $graphRule['operator'] = if ($Rule['Operator']) { $Rule['Operator'] } else { 'equal' }
                $graphRule['comparisonValue'] = if ($null -ne $Rule['ComparisonValue']) {
                    [string]$Rule['ComparisonValue']
                } else {
                    'ok'
                }
            }
            $graphRule
        }
        default {
            $message = "Unknown rule type '$($Rule['Type'])' (File, Registry, ProductCode or Script)"
            $exception = [System.ArgumentException]::new($message)
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception, 'Win32RuleTypeUnknown', $invalidArgument, $Rule)
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
    }
}


function Get-Win32AppRuleSet {
    <#
    .SYNOPSIS
        Gets every Graph rule for one Win32 experiment, in the order Intune lists them.

    .DESCRIPTION
        Detection comes from the experiment's Detection script (if any) followed by its DetectionRules;
        requirements from the legacy Requirement script spec followed by RequirementRules. Script specs
        carry a body under Script (plus Bom); this function encodes them through -Encode, which is where
        the probe header is prepended. An experiment without a single detection rule is refused, as
        Graph would refuse it.

        The rules are written out together once the set is known to have a detection rule, so a refused
        experiment gives no rules at all. A spec that ConvertTo-Win32AppRule refuses ends this function
        with that error.

    .PARAMETER Experiment
        One Win32Apps entry from Experiments.psd1.

    .PARAMETER Encode
        Script block taking the body and a BOM flag and returning the base64 script content.

    .EXAMPLE
        $encode = { param($Body, $Bom) (ConvertTo-ScriptContent -Body $Body -Bom:([bool]$Bom)).Base64 }
        Get-Win32AppRuleSet -Experiment $exp -Encode $encode

        The detection and requirement rules of the experiment in $exp, with each script spec encoded by
        ConvertTo-ScriptContent.

    .INPUTS
        None.

    .OUTPUTS
        System.Collections.Hashtable. One rule as Graph takes it, for each rule of the experiment.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Experiment,

        [Parameter(Mandatory)]
        [scriptblock]$Encode
    )

    $rules = [System.Collections.Generic.List[hashtable]]::new()

    $detectionSpecs = [System.Collections.Generic.List[hashtable]]::new()
    if ($Experiment['Detection']) {
        $detectionSpecs.Add(@{
                Type = 'Script'
                Script = $Experiment['Detection']
                Bom = [bool]$Experiment['Bom']
                RunAs32Bit = [bool]$Experiment['RunAs32Bit']
                EnforceSignatureCheck = [bool]$Experiment['EnforceSignatureCheck']
            })
    }
    foreach ($spec in @($Experiment['DetectionRules'])) { if ($spec) { $detectionSpecs.Add($spec) } }

    $requirementSpecs = [System.Collections.Generic.List[hashtable]]::new()
    if ($Experiment['Requirement']) {
        $requirementSpecs.Add((@{ Type = 'Script' } + $Experiment['Requirement']))
    }
    foreach ($spec in @($Experiment['RequirementRules'])) { if ($spec) { $requirementSpecs.Add($spec) } }

    try {
        foreach ($pair in @(@{ Type = 'detection'; Specs = $detectionSpecs },
                @{ Type = 'requirement'; Specs = $requirementSpecs })) {
            foreach ($spec in $pair['Specs']) {
                $rule = @{} + $spec
                if ($rule['Type'] -eq 'Script' -and $rule['Script']) {
                    $rule['ScriptContent'] = & $Encode $rule['Script'] ([bool]$rule['Bom'])
                }
                $rules.Add((ConvertTo-Win32AppRule -Rule $rule -RuleType $pair['Type'] -ErrorAction Stop))
            }
        }
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }

    if (-not ($rules | Where-Object { $_['ruleType'] -eq 'detection' })) {
        $message = "Experiment $($Experiment['Name']) has no detection rule (Detection script or DetectionRules)"
        $exception = [System.ArgumentException]::new($message)
        $category = [System.Management.Automation.ErrorCategory]::InvalidData
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception, 'Win32DetectionRuleMissing', $category, $Experiment['Name'])
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }
    $rules.ToArray()
}


function ConvertTo-RemediationSchedule {
    <#
    .SYNOPSIS
        Converts a remediation experiment's Schedule into a deviceHealthScriptRunSchedule.

    .DESCRIPTION
        The deviceHealthScriptRunSchedule for a remediation experiment.

        Schedule = @{ Type = 'RunOnce'; DelayMinutes = 20 } becomes a deviceHealthScriptRunOnceSchedule at
        -Now plus the delay, in UTC. Type Daily becomes a daily schedule at that time. Anything else, and
        no Schedule at all, is hourly with Interval (default 1), the kit's original assignment.

    .PARAMETER Schedule
        The experiment's Schedule hashtable, or nothing.

    .PARAMETER Now
        The reference time for a run-once or daily schedule; injected so it can be tested.

    .EXAMPLE
        ConvertTo-RemediationSchedule -Schedule @{ Type = 'RunOnce'; DelayMinutes = 15 }

        A run-once schedule fifteen minutes from now, in UTC.

    .INPUTS
        None.

    .OUTPUTS
        System.Collections.Hashtable. The run schedule as Graph takes it.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [hashtable]$Schedule,

        [datetime]$Now = (Get-Date).ToUniversalTime()
    )

    $type = if ($Schedule) { [string]$Schedule['Type'] } else { '' }
    $delay = if ($Schedule -and $Schedule.ContainsKey('DelayMinutes')) {
        [int]$Schedule['DelayMinutes']
    } else {
        10
    }
    $at = $Now.ToUniversalTime().AddMinutes($delay)
    switch ($type) {
        'RunOnce' {
            @{
                '@odata.type' = '#microsoft.graph.deviceHealthScriptRunOnceSchedule'
                interval = 1
                useUtc = $true
                date = $at.ToString('yyyy-MM-dd')
                time = $at.ToString('HH:mm:ss')
            }
        }
        'Daily' {
            @{
                '@odata.type' = '#microsoft.graph.deviceHealthScriptDailySchedule'
                interval = if ($Schedule['Interval']) { [int]$Schedule['Interval'] } else { 1 }
                useUtc = $true
                time = $at.ToString('HH:mm:ss')
            }
        }
        default {
            @{
                '@odata.type' = '#microsoft.graph.deviceHealthScriptHourlySchedule'
                interval = if ($Schedule -and $Schedule['Interval']) { [int]$Schedule['Interval'] } else { 1 }
            }
        }
    }
}
