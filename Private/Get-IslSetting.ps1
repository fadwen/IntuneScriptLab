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

    .INPUTS
        None.

    .OUTPUTS
        IntuneScriptLab.Settings.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.Settings')]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [object]$Settings,

        [hashtable]$Cache = @{}
    )

    # A settings file that cannot be read, and a value in it that is wrong, end the function
    $found = $null
    try {
        if ($Settings -is [hashtable]) {
            $found = ConvertTo-IslSettingsObject -Table $Settings -Source '-Settings'
        } elseif ($null -ne $Settings) {
            $file = (Resolve-Path -LiteralPath "$Settings" -ErrorAction Stop).ProviderPath
            $fileTable = Import-PowerShellDataFile -LiteralPath $file -ErrorAction Stop
            $found = ConvertTo-IslSettingsObject -Table $fileTable -Source $file
        } else {
            $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
            $folder = if (Test-Path -LiteralPath $resolved -PathType Container) { $resolved }
            else { Split-Path -Path $resolved -Parent }
            if ($Cache.ContainsKey($folder)) {
                $found = $Cache[$folder]
            } else {
                $probe = $folder
                while ($probe) {
                    $candidate = Join-Path -Path $probe -ChildPath 'IntuneScriptLab.settings.psd1'
                    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                        $candidateTable = Import-PowerShellDataFile -LiteralPath $candidate -ErrorAction Stop
                        $found = ConvertTo-IslSettingsObject -Table $candidateTable -Source $candidate
                        break
                    }
                    $probe = Split-Path -Path $probe -Parent
                }
                if (-not $found) { $found = ConvertTo-IslSettingsObject -Table @{} -Source '' }
                $Cache[$folder] = $found
            }
        }
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }

    $found
}
