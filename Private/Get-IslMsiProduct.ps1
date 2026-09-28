function Get-IslMsiProduct {
    <#
    .SYNOPSIS
        Finds an installed Windows Installer product by product code.

    .DESCRIPTION
        Looks the product code up under the Uninstall keys of both registry views of HKLM and under
        HKCU, which is where Windows Installer registers per-machine 64-bit, per-machine 32-bit and
        per-user products. The agent found a 64-bit product and a WOW6432Node one alike
        (W32-MSI-EXISTS, W32-MSI-32BIT) and reported a code that is not installed as not detected
        (W32-MSI-MISSING).

    .PARAMETER ProductCode
        The product code GUID, with or without braces.

    .EXAMPLE
        Get-IslMsiProduct -ProductCode '{FBE4D84C-C935-4F54-B96F-49316CEB5149}'

        The product's display name and version, or nothing when it is not installed.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.MsiProduct')]
    param(
        [Parameter(Mandatory)]
        [string]$ProductCode
    )

    $code = $ProductCode.Trim()
    if (-not $code.StartsWith('{')) { $code = "{$code}" }
    $uninstall = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    $places = @(
        @{ Hive = 'LocalMachine'; View = 'Registry64'; Label = 'HKLM 64-bit' }
        @{ Hive = 'LocalMachine'; View = 'Registry32'; Label = 'HKLM 32-bit' }
        @{ Hive = 'CurrentUser'; View = 'Default'; Label = 'HKCU' }
    )
    foreach ($place in $places) {
        $base = $null
        $key = $null
        try {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($place.Hive, $place.View)
            $key = $base.OpenSubKey("$uninstall\$code")
            if ($key) {
                return [pscustomobject]@{
                    PSTypeName     = 'IntuneScriptLab.MsiProduct'
                    ProductCode    = $code
                    DisplayName    = "$($key.GetValue('DisplayName'))"
                    DisplayVersion = "$($key.GetValue('DisplayVersion'))"
                    View           = $place.Label
                }
            }
        }
        finally {
            if ($key) { $key.Dispose() }
            if ($base) { $base.Dispose() }
        }
    }
}
