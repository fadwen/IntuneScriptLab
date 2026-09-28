function Get-IslHostPath {
    <#
    .SYNOPSIS
        Resolves the Windows PowerShell host the Intune agent would launch for an architecture.

    .DESCRIPTION
        x86 is SysWOW64\WindowsPowerShell\v1.0\powershell.exe on every 64-bit device (native on
        x64, emulated on ARM64). x64 and arm64 are both System32\...\powershell.exe, which is
        whichever native binary the device has, so each is refused on the other CPU. When the
        harness itself is a 32-bit process, System32 is reached through Sysnative.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.Host')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('x86', 'x64', 'arm64')]
        [string]$Architecture
    )

    $osArchitecture = "$([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)"
    $deviceIs64 = [Environment]::Is64BitOperatingSystem
    $relative = 'WindowsPowerShell\v1.0\powershell.exe'

    switch ($Architecture) {
        'x86' {
            if (-not $deviceIs64) { $folder = 'System32' }
            else { $folder = 'SysWOW64' }
        }
        'x64' {
            if ($osArchitecture -ne 'X64') {
                throw ("No x64 PowerShell host on this $osArchitecture device. On Windows on ARM the 64-bit " +
                    "host " +
                    "is the native ARM64 one: use -Architecture arm64")
            }
            $folder = 'System32'
        }
        'arm64' {
            if ($osArchitecture -ne 'Arm64') {
                throw ("This is an $osArchitecture device; there is no ARM64 PowerShell host here. Use " +
                    "-Architecture x64 (or x86)")
            }
            $folder = 'System32'
        }
    }

    # A 32-bit harness process sees SysWOW64 when it asks for System32; Sysnative is the way out
    if ($folder -eq 'System32' -and -not [Environment]::Is64BitProcess -and $deviceIs64) { $folder = 'Sysnative' }

    $path = Join-Path -Path (Join-Path -Path $env:WINDIR -ChildPath $folder) -ChildPath $relative
    if (-not (Test-Path -LiteralPath $path)) { throw "PowerShell host not found: $path" }

    [pscustomobject]@{
        PSTypeName     = 'IntuneScriptLab.Host'
        Architecture   = $Architecture
        Path           = $path
        OSArchitecture = $osArchitecture
        Emulated       = ($Architecture -eq 'x86' -and $osArchitecture -eq 'Arm64')
    }
}
