function Test-IntuneScript {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Checks a PowerShell script for the mistakes Intune turns into silent failures.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.Finding')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName', 'PSPath')]
        [SupportsWildcards()]
        [string[]]$Path,

        [ValidateSet('Auto', 'Detection', 'Remediation', 'PlatformScript', 'Win32Detection', 'Win32Requirement')]
        [string]$ScriptType = 'Auto',

        [ValidateSet('Auto', 'System', 'User')]
        [string]$Context = 'Auto',

        [ValidateSet('Auto', 'x86', 'x64', 'arm64')]
        [string]$Architecture = 'Auto',

        [ValidateLength(0, 1000)]
        [string[]]$IncludeRule,

        [ValidateLength(0, 1000)]
        [string[]]$ExcludeRule,

        [ValidateSet('Information', 'Warning', 'Error')]
        [string]$MinimumSeverity = 'Information',

        [switch]$EnforceSignatureCheck,

        # A settings file path or hashtable; omitted, the nearest IntuneScriptLab.settings.psd1
        # above each script applies, and @{} means none
        [object]$Settings,

        [switch]$IncludeSuppressed
    )

    begin {
        $severityRank = @{ Information = 0; Warning = 1; Error = 2 }
        $settingsCache = @{}
        # -Settings is the same for every script. It is read once, and one that is wrong ends the
        # command here instead of failing each script in turn
        $givenSettings = $null
        if ($PSBoundParameters.ContainsKey('Settings')) {
            try {
                $givenSettings = Get-IslSetting -Path $PWD.Path -Settings $Settings
            } catch {
                $PSCmdlet.ThrowTerminatingError($_)
            }
        }

    }

    process {
        # A path that is not there is reported, and the other paths are still analyzed. It is tested
        # first and reported once: an error that Resolve-Path raised and this command caught would
        # also reach a caller's -ErrorVariable, three records for one path
        $files = foreach ($item in $Path) {
            if (-not (Test-Path -Path $item)) {
                $recordSplat = @{
                    Message = "Cannot find path '$item' because it does not exist."
                    ErrorId = 'PathNotFound'
                    Category = [System.Management.Automation.ErrorCategory]::ObjectNotFound
                    TargetObject = $item
                    ExceptionType = [System.Management.Automation.ItemNotFoundException]
                }
                $PSCmdlet.WriteError((New-IslErrorRecord @recordSplat))
                continue
            }
            try {
                $resolvedItems = @(Resolve-Path -Path $item -ErrorAction Stop)
            } catch {
                $PSCmdlet.WriteError($_)
                continue
            }
            foreach ($resolved in $resolvedItems) {
                if (Test-Path -LiteralPath $resolved.ProviderPath -PathType Container) {
                    Get-ChildItem -LiteralPath $resolved.ProviderPath -Recurse -Filter *.ps1 -File |
                        ForEach-Object { $_.FullName }
                } else { $resolved.ProviderPath }
            }
        }

        foreach ($file in $files) {
            # A script that cannot be analyzed, as when the settings file above it is wrong, is
            # reported, and the next script is still analyzed
            try {
                # Parameters beat the settings file; the settings file beats inference
                $fileSettings = $givenSettings
                if ($null -eq $fileSettings) {
                    $fileSettings = Get-IslSetting -Path $file -Cache $settingsCache
                }
                $include = if ($PSBoundParameters.ContainsKey('IncludeRule')) { $IncludeRule }
                else { $fileSettings.IncludeRule }
                # An explicit -IncludeRule names what to run, so the file's exclusions stand aside for it
                $exclude = if ($PSBoundParameters.ContainsKey('IncludeRule')) { @($ExcludeRule) }
                else { @($ExcludeRule) + @($fileSettings.ExcludeRule) }
                $exclude = @($exclude | Where-Object { $_ })
                $minimum = if ($PSBoundParameters.ContainsKey('MinimumSeverity')) { $MinimumSeverity }
                elseif ($fileSettings.MinimumSeverity) { $fileSettings.MinimumSeverity }
                else { $MinimumSeverity }
                $filters = @{ Include = $include; Exclude = $exclude }
                $rules = foreach ($rule in $script:RuleOrder) {
                    if (Test-IslRuleSelected -RuleName ($rule -replace '^Find-', '') @filters) { $rule }
                }

                $scriptContextSplat = @{
                    Path = $file
                    ScriptType = $ScriptType
                    Context = $Context
                    Architecture = $Architecture
                    Settings = $fileSettings
                }
                # Bound either way it is explicit: the pre-flight passes the policy's own false value
                if ($PSBoundParameters.ContainsKey('EnforceSignatureCheck')) {
                    $signatureText = if ($EnforceSignatureCheck) { 'True' } else { 'False' }
                    $scriptContextSplat.EnforceSignatureCheck = $signatureText
                }
                $scriptContext = Get-IslScriptContext @scriptContextSplat
                Write-Verbose ("$file : $($scriptContext.ScriptType) ($($scriptContext.TypeSource)), " +
                    "$($scriptContext.Context), $($scriptContext.Architecture)")

                $findings = @(foreach ($rule in $rules) {
                        & $rule -Context $scriptContext
                    })
                # Say what was assumed: the wrong type silently skips whole rule sets. The note obeys
                # the rule filters, so -ExcludeRule IslAssumedContext silences it
                $noteWanted = $scriptContext.TypeSource -notin 'parameter', 'settings', 'directive' -and
                (Test-IslRuleSelected -RuleName 'IslAssumedContext' @filters)
                if ($noteWanted) {
                    $findingSplat = @{
                        RuleName = 'IslAssumedContext'
                        Severity = 'Information'
                        Context = $scriptContext
                        Message = ("Analyzed as $($scriptContext.ScriptType) ($($scriptContext.TypeSource)), " +
                            "$($scriptContext.Context) context, $($scriptContext.Architecture): the portal " +
                            'defaults where nothing said otherwise; a deployment through the Graph API or IaC ' +
                            'gets 64-bit SYSTEM. Pass ' +
                            "-ScriptType/-Context/-Architecture or add a '# IntuneScriptLab:' " +
                            'directive if that is wrong')
                        Evidence = ('Portal defaults: platform scripts run as the user in 32-bit, remediations ' +
                            'as SYSTEM in 32-bit, Win32 detection in 64-bit; Graph stores runAs32Bit=false and ' +
                            'runAsAccount=system when omitted (Graph API defaults)')
                    }
                    $findings = @(New-IslFinding @findingSplat) + $findings
                }

                # Severity overrides from the settings file, then the suppressions in the script
                foreach ($finding in $findings) {
                    if ($fileSettings.Severity.ContainsKey($finding.RuleName)) {
                        $finding.Severity = $fileSettings.Severity[$finding.RuleName]
                    }
                }
                $suppressions = @(Get-IslSuppression -Context $scriptContext)
                foreach ($finding in $findings) {
                    foreach ($suppression in $suppressions) {
                        if ($finding.RuleName -like $suppression.Rule -and
                            ($suppression.Line -eq 0 -or $suppression.Line -eq $finding.Line)) {
                            $finding.Suppressed = $true
                            break
                        }
                    }
                }
                $selected = @($findings | Where-Object {
                        $severityRank[$_.Severity] -ge $severityRank[$minimum] -and
                        ($IncludeSuppressed -or -not $_.Suppressed)
                    })
            } catch {
                $PSCmdlet.WriteError($_)
                continue
            }

            foreach ($finding in $selected) { $finding }
        }
    }
}
