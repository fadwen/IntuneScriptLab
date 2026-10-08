function Get-IslHostArchitecture {
    <#
    .SYNOPSIS
        The architecture of this device's 64-bit Windows PowerShell host: x64, or arm64 on Windows on ARM.

    .DESCRIPTION
        The agent runs Win32 detection and requirement scripts in the device's 64-bit host unless
        the rule's "run as 32-bit" option is on. On Windows on ARM that host is the native ARM64
        one and there is no x64 PowerShell at all (Findings, "Windows on ARM"), so the harness
        commands use this as their default architecture instead of a fixed x64 that an ARM64
        device refuses. The 32-bit host (x86) exists on both and is never the answer here.

    .EXAMPLE
        Get-IslHostArchitecture

        x64 on an x64 device, arm64 on a Windows on ARM device.

    .OUTPUTS
        System.String. x64 or arm64, as Get-IslHostPath and the -Architecture parameters name them.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $osArchitecture = "$([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)"
    if ($osArchitecture -eq 'Arm64') { 'arm64' } else { 'x64' }
}
