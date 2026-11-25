function Compare-IntuneDeployedScript {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Reports where a tenant's deployed scripts differ from the copies in a folder or repository.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.DriftResult')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,

        [hashtable]$Map,

        [ValidateSet('Remediation', 'PlatformScript', 'Win32App')]
        [string[]]$Kind = @('Remediation', 'PlatformScript', 'Win32App'),

        [SupportsWildcards()]
        [string[]]$Name = @('*'),

        [string[]]$Id,

        $Settings
    )
    Write-Verbose ("Starting $($MyInvocation.MyCommand.Name) against $Path for $($Kind -join ', ') named " +
        "$($Name -join ', ')$(if ($Id) { " or with id $($Id -join ', ')" })")

    try {
        $root = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        $recordSplat = @{
            Message = "Path must be a folder holding the local scripts: $Path"
            ErrorId = 'LocalPathNotFolder'
            Category = [System.Management.Automation.ErrorCategory]::InvalidArgument
            TargetObject = $Path
            ExceptionType = [System.ArgumentException]
        }
        $PSCmdlet.ThrowTerminatingError((New-IslErrorRecord @recordSplat))
    }
    $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.ps1')
    $folders = @(Get-Item -LiteralPath $root) + @(Get-ChildItem -LiteralPath $root -Recurse -Directory)
    $settingsCache = @{}
    $mapped = @{}
    # Which policies of each list to read; -Id alone selects by id, so whether -Name was given counts
    $wanted = @{ Name = $Name; Id = $Id; NameGiven = $PSBoundParameters.ContainsKey('Name') }
    # Where the local scripts are looked for; Matched collects the -Map keys that found a policy
    $localOptions = @{ Root = $root; LocalFile = $files; LocalFolder = $folders; Map = $Map; Matched = $mapped }
    # What every comparison of a script needs besides the script itself
    $compareOptions = @{ Root = $root; SettingsCache = $settingsCache }
    if ($PSBoundParameters.ContainsKey('Settings')) { $compareOptions.Settings = $Settings }

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
                $policy = Invoke-IslGraphRequest -Uri "$remediations/$summaryId"
                $enforceSignature = Get-IslPropertyValue -InputObject $policy -Name 'enforceSignatureCheck'
                $policySettings = @{
                    RunAsAccount = Get-IslPropertyValue -InputObject $policy -Name 'runAsAccount'
                    RunAs32Bit = Get-IslPropertyValue -InputObject $policy -Name 'runAs32Bit'
                    EnforceSignatureCheck = $enforceSignature
                }
                $detectFind = @{ Policy = $policy; Role = 'detection'; Pattern = '^(?i)detect' }
                $detectSplat = @{
                    PolicyKind = 'Remediation'
                    Policy = $policy
                    Role = 'detection'
                    Content = Get-IslPropertyValue -InputObject $policy -Name 'detectionScriptContent'
                    Candidates = Find-IslLocalScript @detectFind @localOptions
                }
                Compare-IslPolicyScript @detectSplat @policySettings @compareOptions
                $remediateFind = @{ Policy = $policy; Role = 'remediation'; Pattern = '^(?i)remediat' }
                $remediateSplat = @{
                    PolicyKind = 'Remediation'
                    Policy = $policy
                    Role = 'remediation'
                    Content = Get-IslPropertyValue -InputObject $policy -Name 'remediationScriptContent'
                    Candidates = Find-IslLocalScript @remediateFind @localOptions
                }
                Compare-IslPolicyScript @remediateSplat @policySettings @compareOptions
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
                $policy = Invoke-IslGraphRequest -Uri "$scripts/$summaryId"
                $enforceSignature = Get-IslPropertyValue -InputObject $policy -Name 'enforceSignatureCheck'
                $scriptSplat = @{
                    PolicyKind = 'PlatformScript'
                    Policy = $policy
                    Role = 'script'
                    Content = Get-IslPropertyValue -InputObject $policy -Name 'scriptContent'
                    RunAsAccount = Get-IslPropertyValue -InputObject $policy -Name 'runAsAccount'
                    RunAs32Bit = Get-IslPropertyValue -InputObject $policy -Name 'runAs32Bit'
                    EnforceSignatureCheck = $enforceSignature
                    Candidates = Find-IslLocalScript -Policy $policy -Role 'script' @localOptions
                }
                Compare-IslPolicyScript @scriptSplat @compareOptions
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
                $app = Invoke-IslGraphRequest -Uri "$apps/$summaryId"
                $scriptType = '#microsoft.graph.win32LobAppPowerShellScriptDetection'
                $detectionRules = @(
                    Get-IslPropertyValue -InputObject $app -Name 'detectionRules' | Where-Object {
                        "$(Get-IslPropertyValue -InputObject $_ -Name '@odata.type')" -eq $scriptType
                    })
                $detectionFind = @{ Policy = $app; Role = 'detection'; Pattern = '^(?i)detect' }
                $detectionFiles = @(Find-IslLocalScript @detectionFind @localOptions)
                for ($index = 0; $index -lt $detectionRules.Count; $index++) {
                    $candidateSplat = @{
                        Candidate = $detectionFiles; RuleCount = $detectionRules.Count; Index = $index
                    }
                    $candidates = Select-IslRuleCandidate @candidateSplat
                    $rule = $detectionRules[$index]
                    $signatureCheck = Get-IslPropertyValue -InputObject $rule -Name 'enforceSignatureCheck'
                    $detectSplat = @{
                        PolicyKind = 'Win32App'
                        Policy = $app
                        Role = 'detection'
                        Content = Get-IslPropertyValue -InputObject $rule -Name 'scriptContent'
                        Candidates = $candidates
                        RunAsAccount = 'system'
                        RunAs32Bit = Get-IslPropertyValue -InputObject $rule -Name 'runAs32Bit'
                        EnforceSignatureCheck = $signatureCheck
                        SkipContext = $true
                    }
                    Compare-IslPolicyScript @detectSplat @compareOptions
                }
                if ($detectionRules.Count -eq 0 -and $detectionFiles.Count -gt 0) {
                    $noRuleSplat = @{
                        PolicyKind = 'Win32App'; Policy = $app; Role = 'detection'; Content = ''
                        Candidates = $detectionFiles
                    }
                    Compare-IslPolicyScript @noRuleSplat @compareOptions
                }
                $requirementType = '#microsoft.graph.win32LobAppPowerShellScriptRequirement'
                $requirementRules = @(
                    Get-IslPropertyValue -InputObject $app -Name 'requirementRules' | Where-Object {
                        "$(Get-IslPropertyValue -InputObject $_ -Name '@odata.type')" -eq $requirementType
                    })
                $requirementFind = @{ Policy = $app; Role = 'requirement'; Pattern = '^(?i)requirement' }
                $requirementFiles = @(Find-IslLocalScript @requirementFind @localOptions)
                if ($requirementRules.Count -eq 0) {
                    $noRuleSplat = @{
                        PolicyKind = 'Win32App'; Policy = $app; Role = 'requirement'; Content = ''
                        Candidates = $requirementFiles
                    }
                    Compare-IslPolicyScript @noRuleSplat @compareOptions
                }
                for ($index = 0; $index -lt $requirementRules.Count; $index++) {
                    $candidateSplat = @{
                        Candidate = $requirementFiles; RuleCount = $requirementRules.Count; Index = $index
                    }
                    $candidates = Select-IslRuleCandidate @candidateSplat
                    $rule = $requirementRules[$index]
                    $signatureCheck = Get-IslPropertyValue -InputObject $rule -Name 'enforceSignatureCheck'
                    $requirementSplat = @{
                        PolicyKind = 'Win32App'
                        Policy = $app
                        Role = 'requirement'
                        Content = Get-IslPropertyValue -InputObject $rule -Name 'scriptContent'
                        Candidates = $candidates
                        RunAsAccount = Get-IslPropertyValue -InputObject $rule -Name 'runAsAccount'
                        RunAs32Bit = Get-IslPropertyValue -InputObject $rule -Name 'runAs32Bit'
                        EnforceSignatureCheck = $signatureCheck
                    }
                    Compare-IslPolicyScript @requirementSplat @compareOptions
                }
            } catch {
                $PSCmdlet.ThrowTerminatingError($_)
            }
            $policyOutput
        }
    }

    $unmatched = @(if ($Map) { $Map.Keys | Where-Object { -not $mapped.ContainsKey("$_") } })
    foreach ($key in $unmatched) {
        $entry = $Map[$key]
        $first = if ($entry -is [hashtable]) { @($entry.Values)[0] } else { $entry }
        $orphan = [pscustomobject]@{ displayName = "$key"; id = ''; lastModifiedDateTime = $null }
        $orphanSplat = @{
            PolicyKind = ''; Policy = $orphan; Role = 'policy'; State = 'NotInTenant'; LocalPath = "$first"
            Detail     = "no policy named '$key' among the kinds compared ($($Kind -join ', '))"
        }
        ConvertTo-IslDriftResult @orphanSplat
    }
    Write-Verbose "Completed $($MyInvocation.MyCommand.Name)"
}
