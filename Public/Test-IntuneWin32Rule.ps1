function Test-IntuneWin32Rule {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Applies a Win32 app file, registry or MSI rule to this device the way the Intune agent does.
    #>
    [CmdletBinding(DefaultParameterSetName = 'File')]
    [OutputType('IntuneScriptLab.RuleResult')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'File')]
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = 'File')]
        [string]$FileOrFolderName,

        [Parameter(Mandatory, ParameterSetName = 'File')]
        [ValidateSet('Exists', 'DoesNotExist', 'Version', 'SizeInMB', 'ModifiedDate', 'CreatedDate')]
        [string]$FileOperation,

        [Parameter(Mandatory, ParameterSetName = 'Registry')]
        [string]$KeyPath,

        [Parameter(ParameterSetName = 'Registry')]
        [string]$ValueName,

        [Parameter(Mandatory, ParameterSetName = 'Registry')]
        [ValidateSet('Exists', 'DoesNotExist', 'String', 'Integer', 'Version')]
        [string]$RegistryOperation,

        [Parameter(Mandatory, ParameterSetName = 'ProductCode')]
        [string]$ProductCode,

        [Parameter(ParameterSetName = 'File')]
        [Parameter(ParameterSetName = 'Registry')]
        [Parameter(ParameterSetName = 'ProductCode')]
        [ValidateSet('Equal', 'NotEqual', 'GreaterThan', 'GreaterThanOrEqual', 'LessThan', 'LessThanOrEqual')]
        [string]$Operator,

        [Parameter(ParameterSetName = 'File')]
        [Parameter(ParameterSetName = 'Registry')]
        [Parameter(ParameterSetName = 'ProductCode')]
        [AllowEmptyString()]
        [string]$Value,

        [Parameter(ParameterSetName = 'File')]
        [Parameter(ParameterSetName = 'Registry')]
        [switch]$Check32BitOn64System,

        [ValidateSet('Detection', 'Requirement')]
        [string]$RuleType = 'Detection',

        [Parameter(Mandatory, ParameterSetName = 'Rule')]
        [hashtable]$Rule
    )
    Write-Verbose "Starting $($MyInvocation.MyCommand.Name) ($($PSCmdlet.ParameterSetName))"

    if ($PSCmdlet.ParameterSetName -eq 'Rule') {
        $splat = ConvertFrom-IslRuleSpec -Rule $Rule
        if ($Rule.ContainsKey('RuleType') -and $Rule.RuleType) { $splat.RuleType = $Rule.RuleType }
        else { $splat.RuleType = $RuleType }
        return Test-IntuneWin32Rule @splat
    }

    $kind = $PSCmdlet.ParameterSetName
    $operation = switch ($kind) {
        'File' { $FileOperation }
        'Registry' { $RegistryOperation }
        'ProductCode' { if ($Operator) { 'Version' } else { 'Exists' } }
    }
    $result = [pscustomobject]@{
        PSTypeName           = 'IntuneScriptLab.RuleResult'
        Met                  = $false
        Kind                 = $kind
        RuleType             = $RuleType
        Target               = ''
        Operation            = $operation
        Operator             = $Operator
        Value                = $Value
        Actual               = $null
        Check32BitOn64System = [bool]$Check32BitOn64System
        Reason               = ''
    }
    $needsValue = $operation -notin 'Exists', 'DoesNotExist'
    if ($needsValue -and -not $Operator) {
        throw "A $kind $operation rule needs -Operator and -Value"
    }
    if ($needsValue -and -not $PSBoundParameters.ContainsKey('Value')) {
        throw "A $kind $operation rule needs -Value"
    }

    switch ($kind) {
        'File' {
            $folder = Resolve-IslRulePath -Path $Path -Check32BitOn64System $Check32BitOn64System
            $target = Join-Path -Path $folder -ChildPath $FileOrFolderName
            $result.Target = $target
            $exists = Test-Path -LiteralPath $target
            $result.Actual = if ($exists) { 'present' } else { 'absent' }
            switch ($operation) {
                'Exists' {
                    $result.Met = $exists
                    $result.Reason = if ($exists) { "$target exists" } else { "$target does not exist" }
                }
                'DoesNotExist' {
                    # The agent cannot evaluate this operation on a file: never met (W32-FILE-NOTEXIST,
                    # W32-FILE-NOTEXIST-FALSE), so it is reported as it would be on the device
                    $result.Reason = if ($exists) {
                        ("$target exists, and the agent reports a file DoesNotExist $($RuleType.ToLower()) " +
                            'rule on a present file as an invalid rule (0x87D30004, W32-FILE-NOTEXIST-FALSE)')
                    }
                    else {
                        ("$target is absent, but the agent evaluates a file DoesNotExist " +
                            "$($RuleType.ToLower()) rule as not met even then (W32-FILE-NOTEXIST); use a " +
                            'registry DoesNotExist rule or a script instead')
                    }
                }
                default {
                    if (-not $exists) {
                        $result.Reason = "$target does not exist, so the $operation rule is not met"
                        break
                    }
                    $item = Get-Item -LiteralPath $target
                    switch ($operation) {
                        'Version' {
                            $info = $item.VersionInfo
                            if (-not $info -or -not $info.FileVersion) {
                                $result.Actual = ''
                                $result.Reason = "$target has no version resource, so the Version rule is not met"
                                break
                            }
                            $fileVersion = '{0}.{1}.{2}.{3}' -f $info.FileMajorPart, $info.FileMinorPart,
                                $info.FileBuildPart, $info.FilePrivatePart
                            $comparisonSplat = @{
                                Actual = $fileVersion; Expected = $Value; Type = 'Version'; Operator = $Operator
                            }
                            $comparison = Compare-IslRuleValue @comparisonSplat
                            $result.Actual = $fileVersion
                            $result.Met = $comparison.Met
                            $result.Reason = "File version $($comparison.Reason)"
                        }
                        'SizeInMB' {
                            $sizeMb = [math]::Floor($item.Length / 1MB)
                            $comparisonSplat = @{
                                Actual = $sizeMb; Expected = $Value; Type = 'Integer'; Operator = $Operator
                            }
                            $comparison = Compare-IslRuleValue @comparisonSplat
                            $result.Actual = "$sizeMb"
                            $result.Met = $comparison.Met
                            $result.Reason = "Size $($item.Length) bytes is $sizeMb MiB rounded down: " +
                                $comparison.Reason
                        }
                        default {
                            $stamp = if ($operation -eq 'ModifiedDate') { $item.LastWriteTimeUtc }
                            else { $item.CreationTimeUtc }
                            $comparisonSplat = @{
                                Actual = $stamp; Expected = $Value; Type = 'DateTime'; Operator = $Operator
                            }
                            $comparison = Compare-IslRuleValue @comparisonSplat
                            $result.Actual = $stamp.ToString('o')
                            $result.Met = $comparison.Met
                            $result.Reason = "$operation $($comparison.Reason)"
                        }
                    }
                }
            }
        }
        'Registry' {
            $view = if ($Check32BitOn64System -and [Environment]::Is64BitOperatingSystem) { 'Registry32' }
            elseif ([Environment]::Is64BitOperatingSystem) { 'Registry64' }
            else { 'Default' }
            $hiveName, $subKey = $KeyPath -split '\\', 2
            $hive = switch -Regex ($hiveName) {
                '^(HKEY_LOCAL_MACHINE|HKLM)$' { 'LocalMachine' }
                '^(HKEY_CURRENT_USER|HKCU)$' { 'CurrentUser' }
                '^(HKEY_CLASSES_ROOT|HKCR)$' { 'ClassesRoot' }
                '^(HKEY_USERS|HKU)$' { 'Users' }
                '^(HKEY_CURRENT_CONFIG|HKCC)$' { 'CurrentConfig' }
                default { throw "Registry key path must start with a hive (HKEY_LOCAL_MACHINE\...): $KeyPath" }
            }
            $result.Target = if ($ValueName) { "$KeyPath : $ValueName" } else { $KeyPath }
            $viewLabel = if ($view -eq 'Registry32') { '32-bit view' } else { '64-bit view' }
            $base = $null
            $key = $null
            try {
                $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, $view)
                $key = if ($subKey) { $base.OpenSubKey($subKey) } else { $base }
                $keyExists = $null -ne $key
                $valueExists = $keyExists -and $ValueName -and ($key.GetValueNames() -contains $ValueName)
                $data = if ($valueExists) { $key.GetValue($ValueName) } else { $null }
            }
            finally {
                if ($key -and $key -ne $base) { $key.Dispose() }
                if ($base) { $base.Dispose() }
            }
            $present = if ($ValueName) { $valueExists } else { $keyExists }
            $what = if ($ValueName) { 'value' } else { 'key' }
            $result.Actual = if ($ValueName -and $valueExists) { "$data" }
            elseif ($present) { 'present' } else { 'absent' }
            switch ($operation) {
                'Exists' {
                    $result.Met = $present
                    $result.Reason = "The $what $(if ($present) { 'exists' } else { 'does not exist' }) " +
                        "in the $viewLabel"
                }
                'DoesNotExist' {
                    $result.Met = -not $present
                    $result.Reason = "The $what $(if ($present) { 'exists' } else { 'does not exist' }) " +
                        "in the $viewLabel (registry DoesNotExist is evaluated, W32-REG-KEY-NOTEXIST)"
                }
                default {
                    if (-not $ValueName) { throw "A registry $operation rule needs -ValueName" }
                    if (-not $valueExists) {
                        $result.Reason = "The value does not exist in the $viewLabel, so the rule is not met"
                        break
                    }
                    $comparisonSplat = @{
                        Actual = $data; Expected = $Value; Type = $operation; Operator = $Operator
                    }
                    $comparison = Compare-IslRuleValue @comparisonSplat
                    $result.Met = $comparison.Met
                    $result.Reason = "Value in the ${viewLabel}: $($comparison.Reason)"
                }
            }
        }
        'ProductCode' {
            $result.Target = $ProductCode
            $product = Get-IslMsiProduct -ProductCode $ProductCode
            if (-not $product) {
                $result.Actual = 'not installed'
                $result.Reason = "No installed product has code $ProductCode (HKLM 64-bit, HKLM 32-bit, HKCU)"
                break
            }
            $result.Actual = $product.DisplayVersion
            if (-not $Operator) {
                $result.Met = $true
                $result.Reason = "$($product.DisplayName) $($product.DisplayVersion) is installed " +
                    "($($product.View))"
                break
            }
            $comparisonSplat = @{
                Actual = $product.DisplayVersion; Expected = $Value; Type = 'Version'; Operator = $Operator
            }
            $comparison = Compare-IslRuleValue @comparisonSplat
            $result.Met = $comparison.Met
            $result.Reason = "$($product.DisplayName) is installed ($($product.View)); version " +
                $comparison.Reason
        }
    }

    Write-Verbose "Completed $($MyInvocation.MyCommand.Name): $($result.Reason)"
    $result
}
