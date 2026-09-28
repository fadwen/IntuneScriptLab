function Get-IslDeviceFact {
    <#
    .SYNOPSIS
        Reads the device facts the Win32 base requirements compare against.

    .DESCRIPTION
        Architecture (x86, x64, arm64 from the OS architecture), the Windows build number, free space
        on the system drive in MB, physical memory in MB, logical processor count and the CPU's rated
        speed in MHz. One place to mock in tests, since every value is machine-specific.

    .EXAMPLE
        Get-IslDeviceFact

        The facts of this device as an IntuneScriptLab.DeviceFact object.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.DeviceFact')]
    param()

    $osArchitecture = "$([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)"
    $architecture = switch ($osArchitecture) {
        'Arm64' { 'arm64' }
        'X64' { 'x64' }
        default { 'x86' }
    }
    $systemDrive = if ($env:SystemDrive) { $env:SystemDrive } else { 'C:' }
    $drive = [System.IO.DriveInfo]::new($systemDrive)
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    $processor = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $build = [Environment]::OSVersion.Version.Build
    $versionKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $currentBuild = Get-ItemProperty -Path $versionKey -Name CurrentBuildNumber -ErrorAction SilentlyContinue
    if ($currentBuild -and "$($currentBuild.CurrentBuildNumber)" -match '^\d+$') {
        $build = [int]$currentBuild.CurrentBuildNumber
    }

    [pscustomobject]@{
        PSTypeName      = 'IntuneScriptLab.DeviceFact'
        Architecture    = $architecture
        Build           = $build
        FreeDiskSpaceMB = [long][math]::Floor($drive.AvailableFreeSpace / 1MB)
        MemoryMB        = if ($computer) { [long][math]::Floor($computer.TotalPhysicalMemory / 1MB) } else { 0 }
        Processors      = [Environment]::ProcessorCount
        CpuSpeedMHz     = if ($processor) { [int]$processor.MaxClockSpeed } else { 0 }
    }
}
