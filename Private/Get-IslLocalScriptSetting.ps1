function Get-IslLocalScriptSetting {
    <#
    .SYNOPSIS
    Gets the run settings that a local script states for itself.

    .DESCRIPTION
    For Compare-IntuneDeployedScript, which compares how a local script expects to run with how
    its tenant policy runs it. Only explicit settings count: a directive in the file, such as
    "# IntuneScriptLab: Context=User Architecture=x86", and then the Context, Architecture and
    EnforceSignatureCheck of the settings that Get-IslSetting finds for the file. A setting that
    neither gives is left out.

    .PARAMETER File
    The local script's full path.

    .PARAMETER Cache
    The settings files already read, by folder, which Get-IslSetting fills and reuses.

    .PARAMETER Settings
    The caller's -Settings, a settings file path or hashtable. Leave it out when the caller gave
    none.

    .EXAMPLE
    Get-IslLocalScriptSetting -File $file -Cache $settingsCache

    @{ Context = 'User' } for a script with the directive Context=User and no settings file.

    .INPUTS
    None.

    .OUTPUTS
    System.Collections.Hashtable. The explicit settings, by name.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$File,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [hashtable]$Cache,

        [Parameter()]
        [object]$Settings
    )

    $directive = @{}
    try {
        $text = [System.IO.File]::ReadAllText($File)
        $settingSplat = @{ Path = $File; Cache = $Cache; ErrorAction = 'Stop' }
        if ($PSBoundParameters.ContainsKey('Settings')) { $settingSplat.Settings = $Settings }
        $fileSettings = Get-IslSetting @settingSplat
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
    foreach ($match in [regex]::Matches($text, '(?m)^\s*#\s*IntuneScriptLab\s*:\s*(.+)$')) {
        foreach ($pair in ($match.Groups[1].Value -split '[\s;,]+')) {
            if ($pair -match '^(Context|Architecture|EnforceSignatureCheck)=(\w+)$') {
                $directive[$Matches[1]] = $Matches[2]
            }
        }
    }
    $explicit = @{}
    foreach ($key in 'Context', 'Architecture', 'EnforceSignatureCheck') {
        $fileValue = Get-IslPropertyValue -InputObject $fileSettings -Name $key
        if ($directive.ContainsKey($key)) {
            $explicit[$key] = $directive[$key]
        } elseif ($null -ne $fileValue -and "$fileValue" -ne '') {
            $explicit[$key] = $fileValue
        }
    }
    $explicit
}
