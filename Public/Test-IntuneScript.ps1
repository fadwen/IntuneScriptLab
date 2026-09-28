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

        [string[]]$IncludeRule,

        [string[]]$ExcludeRule,

        [ValidateSet('Information', 'Warning', 'Error')]
        [string]$MinimumSeverity = 'Information',

        [switch]$EnforceSignatureCheck,

        # A settings file path or hashtable; omitted, the nearest IntuneScriptLab.settings.psd1
        # above each script applies, and @{} means none
        $Settings,

        [switch]$IncludeSuppressed
    )

    begin {
        $severityRank = @{ Information = 0; Warning = 1; Error = 2 }
        $settingsCache = @{}

        function Test-RuleSelected {
            param([string]$RuleName, [string[]]$Include, [string[]]$Exclude)
            if ($Include -and -not ($Include | Where-Object { $RuleName -like $_ })) { return $false }
            if ($Exclude -and ($Exclude | Where-Object { $RuleName -like $_ })) { return $false }
            $true
        }
    }

    process {
        $files = foreach ($item in $Path) {
            foreach ($resolved in (Resolve-Path -Path $item -ErrorAction Stop)) {
                if (Test-Path -LiteralPath $resolved.ProviderPath -PathType Container) {
                    Get-ChildItem -LiteralPath $resolved.ProviderPath -Recurse -Filter *.ps1 -File |
                        ForEach-Object FullName
                }
                else { $resolved.ProviderPath }
            }
        }

        foreach ($file in $files) {
            # Parameters beat the settings file; the settings file beats inference
            $settingsSplat = @{ Path = $file; Cache = $settingsCache }
            if ($PSBoundParameters.ContainsKey('Settings')) { $settingsSplat.Settings = $Settings }
            $fileSettings = Get-IslSetting @settingsSplat
            $include = if ($PSBoundParameters.ContainsKey('IncludeRule')) { $IncludeRule }
            else { $fileSettings.IncludeRule }
            $exclude = @($ExcludeRule) + @($fileSettings.ExcludeRule) | Where-Object { $_ }
            $minimum = if ($PSBoundParameters.ContainsKey('MinimumSeverity')) { $MinimumSeverity }
            elseif ($fileSettings.MinimumSeverity) { $fileSettings.MinimumSeverity }
            else { $MinimumSeverity }
            $filters = @{ Include = $include; Exclude = $exclude }
            $rules = foreach ($rule in $script:RuleOrder) {
                if (Test-RuleSelected -RuleName ($rule -replace '^Find-', '') @filters) { $rule }
            }

            $scriptContextSplat = @{
                Path         = $file
                ScriptType   = $ScriptType
                Context      = $Context
                Architecture = $Architecture
                Settings     = $fileSettings
            }
            if ($EnforceSignatureCheck) { $scriptContextSplat.EnforceSignatureCheck = 'True' }
            $scriptContext = Get-IslScriptContext @scriptContextSplat
            Write-Verbose ("$file : $($scriptContext.ScriptType) ($($scriptContext.TypeSource)), " +
                "$($scriptContext.Context), $($scriptContext.Architecture)")

            $findings = @(foreach ($rule in $rules) {
                    & $rule -Context $scriptContext
                })
            # Say what was assumed: the wrong type silently skips whole rule sets. The note obeys
            # the rule filters, so -ExcludeRule IslAssumedContext silences it
            $noteWanted = $scriptContext.TypeSource -notin 'parameter', 'settings' -and
                (Test-RuleSelected -RuleName 'IslAssumedContext' @filters)
            if ($noteWanted) {
                $findingSplat = @{
                    RuleName = 'IslAssumedContext'
                    Severity = 'Information'
                    Context  = $scriptContext
                    Message  = ("Analyzed as $($scriptContext.ScriptType) ($($scriptContext.TypeSource)), " +
                        "$($scriptContext.Context) context, $($scriptContext.Architecture): the portal " +
                        'defaults; a deployment through the Graph API or IaC gets 64-bit SYSTEM. Pass ' +
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
            $findings | Where-Object {
                $severityRank[$_.Severity] -ge $severityRank[$minimum] -and
                ($IncludeSuppressed -or -not $_.Suppressed)
            }
        }
    }
}
