function Compare-IslScriptSetting {
    <#
    .SYNOPSIS
    Compares the run settings a local script states with those of its tenant policy.

    .DESCRIPTION
    For Compare-IntuneDeployedScript. Each setting the script states for itself
    (Get-IslLocalScriptSetting) is compared with the policy's: Context with runAsAccount (user is
    User, anything else System), Architecture with runAs32Bit (x86 or x64), and
    EnforceSignatureCheck with the policy's flag, where true, 1 and yes count as true. Each
    setting that differs gives one note. A setting the script does not state is not compared.

    .PARAMETER File
    The local script's full path.

    .PARAMETER RunAsAccount
    The policy's runAsAccount.

    .PARAMETER RunAs32Bit
    The policy's runAs32Bit.

    .PARAMETER EnforceSignatureCheck
    The policy's enforceSignatureCheck.

    .PARAMETER SkipContext
    Leaves Context out of the comparison, for a Win32 app's detection script, which always runs
    as SYSTEM whatever the app's install context.

    .PARAMETER Cache
    The settings files already read, by folder.

    .PARAMETER Settings
    The caller's -Settings. Leave it out when the caller gave none.

    .EXAMPLE
    Compare-IslScriptSetting -File $file -RunAsAccount 'system' -Cache $settingsCache

    'Context=User locally, the policy runs as System' for a script with the directive Context=User.

    .INPUTS
    None.

    .OUTPUTS
    System.String. One note for each setting that differs.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$File,

        [Parameter()]
        [AllowNull()]
        [object]$RunAsAccount,

        [Parameter()]
        [AllowNull()]
        [object]$RunAs32Bit,

        [Parameter()]
        [AllowNull()]
        [object]$EnforceSignatureCheck,

        [Parameter()]
        [switch]$SkipContext,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [hashtable]$Cache,

        [Parameter()]
        [object]$Settings
    )

    $localSplat = @{ File = $File; Cache = $Cache }
    if ($PSBoundParameters.ContainsKey('Settings')) { $localSplat.Settings = $Settings }
    try {
        $local = Get-IslLocalScriptSetting @localSplat
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
    foreach ($key in @($local.Keys)) {
        switch ($key) {
            'Context' {
                if ($SkipContext) { continue }
                $tenantContext = if ("$RunAsAccount" -eq 'user') { 'User' } else { 'System' }
                if ("$($local['Context'])" -ne $tenantContext) {
                    "Context=$($local['Context']) locally, the policy runs as $tenantContext"
                }
            }
            'Architecture' {
                $tenantArchitecture = if ([bool]$RunAs32Bit) { 'x86' } else { 'x64' }
                $localArchitecture = if ("$($local['Architecture'])" -eq 'x86') { 'x86' } else { 'x64' }
                if ($localArchitecture -ne $tenantArchitecture) {
                    "Architecture=$($local['Architecture']) locally, the policy runs $tenantArchitecture"
                }
            }
            'EnforceSignatureCheck' {
                $localFlag = "$($local['EnforceSignatureCheck'])" -in 'true', '1', 'yes'
                if ($localFlag -ne [bool]$EnforceSignatureCheck) {
                    "EnforceSignatureCheck=$localFlag locally, $([bool]$EnforceSignatureCheck) on the policy"
                }
            }
        }
    }
}
