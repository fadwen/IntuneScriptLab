function Get-IslSetting {
    <#
    .SYNOPSIS
        Finds and validates the IntuneScriptLab.settings.psd1 that applies to a script.

    .DESCRIPTION
        Settings travel with the scripts: a file named IntuneScriptLab.settings.psd1 in the
        script's folder or any folder above it (the nearest wins) sets what a team would
        otherwise repeat on every call. Keys, all optional:

            ExcludeRule           rule names to skip (wildcards)
            IncludeRule           rule names to run, everything else skipped (wildcards)
            MinimumSeverity       Information, Warning or Error
            Severity              @{ RuleName = 'Information' | 'Warning' | 'Error' } overrides
            ScriptType            Detection, Remediation, PlatformScript, Win32Detection,
                                  Win32Requirement: the type when a script's directive says nothing
            Context               System or User, the same way
            Architecture          x86, x64 or arm64, the same way
            EnforceSignatureCheck $true or $false, the same way

        Explicit parameters beat settings, and a directive in a script beats the type, context,
        architecture and signature settings. -Settings takes a file path or a hashtable instead of
        the search; an empty hashtable means "no settings".

    .PARAMETER Path
        The script (or folder) the settings are looked up for.

    .PARAMETER Settings
        A settings file path or a hashtable in the file's shape, instead of searching.

    .PARAMETER Cache
        A hashtable the caller keeps across scripts so each folder is searched once.

    .EXAMPLE
        Get-IslSetting -Path .\Remediations\Widget\Detect.ps1

        The nearest settings file above Detect.ps1, validated, or an empty settings object.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.Settings')]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        $Settings,

        [hashtable]$Cache = @{}
    )

    $validTypes = 'Detection', 'Remediation', 'PlatformScript', 'Win32Detection', 'Win32Requirement'
    $validSeverities = 'Information', 'Warning', 'Error'
    $knownKeys = 'ExcludeRule', 'IncludeRule', 'MinimumSeverity', 'Severity', 'ScriptType', 'Context',
    'Architecture', 'EnforceSignatureCheck'

    function ConvertTo-SettingsObject {
        param([hashtable]$Table, [string]$Source)
        $unknown = @($Table.Keys | Where-Object { $_ -notin $knownKeys })
        if ($unknown) {
            Write-Warning "Unknown settings key(s) in ${Source}: $($unknown -join ', ')"
        }
        # Every key is optional. An index reads a key that is not there as $null, where member
        # access is an error under strict mode
        $minimumSeverity = $Table['MinimumSeverity']
        $scriptType = $Table['ScriptType']
        $context = $Table['Context']
        $architecture = $Table['Architecture']
        $severityTable = $Table['Severity']
        if ($minimumSeverity -and "$minimumSeverity" -notin $validSeverities) {
            throw "${Source}: MinimumSeverity must be one of $($validSeverities -join ', ')"
        }
        if ($scriptType -and "$scriptType" -notin $validTypes) {
            throw "${Source}: ScriptType must be one of $($validTypes -join ', ')"
        }
        if ($context -and "$context" -notin 'System', 'User') {
            throw "${Source}: Context must be System or User"
        }
        if ($architecture -and "$architecture" -notin 'x86', 'x64', 'arm64') {
            throw "${Source}: Architecture must be x86, x64 or arm64"
        }
        $severity = @{}
        $severityKeys = if ($severityTable) { @($severityTable.Keys | Where-Object { $null -ne $_ }) } else { @() }
        foreach ($key in $severityKeys) {
            if ("$($severityTable[$key])" -notin $validSeverities) {
                throw "${Source}: Severity for $key must be one of $($validSeverities -join ', ')"
            }
            $severity[$key] = "$($severityTable[$key])"
        }
        [pscustomobject]@{
            PSTypeName            = 'IntuneScriptLab.Settings'
            Source                = $Source
            ExcludeRule           = @($Table['ExcludeRule'] | Where-Object { $_ })
            IncludeRule           = @($Table['IncludeRule'] | Where-Object { $_ })
            MinimumSeverity       = if ($minimumSeverity) { "$minimumSeverity" } else { $null }
            Severity              = $severity
            ScriptType            = if ($scriptType) { "$scriptType" } else { $null }
            Context               = if ($context) { "$context" } else { $null }
            Architecture          = if ($architecture) { "$architecture" } else { $null }
            EnforceSignatureCheck = if ($Table.ContainsKey('EnforceSignatureCheck')) {
                [bool]$Table['EnforceSignatureCheck']
            }
            else { $null }
        }
    }

    if ($null -ne $Settings) {
        if ($Settings -is [hashtable]) { return ConvertTo-SettingsObject -Table $Settings -Source '-Settings' }
        $file = (Resolve-Path -LiteralPath "$Settings" -ErrorAction Stop).ProviderPath
        return ConvertTo-SettingsObject -Table (Import-PowerShellDataFile -LiteralPath $file) -Source $file
    }

    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    $folder = if (Test-Path -LiteralPath $resolved -PathType Container) { $resolved }
    else { Split-Path -Path $resolved -Parent }
    if ($Cache.ContainsKey($folder)) { return $Cache[$folder] }

    $found = $null
    $probe = $folder
    while ($probe) {
        $candidate = Join-Path -Path $probe -ChildPath 'IntuneScriptLab.settings.psd1'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $candidateTable = Import-PowerShellDataFile -LiteralPath $candidate
            $found = ConvertTo-SettingsObject -Table $candidateTable -Source $candidate
            break
        }
        $probe = Split-Path -Path $probe -Parent
    }
    if (-not $found) { $found = ConvertTo-SettingsObject -Table @{} -Source '' }
    $Cache[$folder] = $found
    $found
}
