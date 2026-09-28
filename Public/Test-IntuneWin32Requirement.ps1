function Test-IntuneWin32Requirement {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Checks a Win32 app's base requirements against this device the way the Intune agent reports them.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.ApplicabilityResult')]
    param(
        [ValidateSet('x86', 'x64', 'arm64')]
        [string[]]$Architecture,

        [ValidateSet('1607', '1703', '1709', '1803', '1809', '1903', '1909', '2004', '20H2', '21H1', '21H2',
            '22H2', 'Windows11_21H2', 'Windows11_22H2', 'Windows11_23H2', 'Windows11_24H2', 'Windows11_25H2')]
        [string]$MinimumWindowsRelease,

        [ValidateRange(1, [long]::MaxValue)]
        [long]$MinimumFreeDiskSpaceMB,

        [ValidateRange(1, [long]::MaxValue)]
        [long]$MinimumMemoryMB,

        [ValidateRange(1, 4096)]
        [int]$MinimumProcessors,

        [ValidateRange(1, [int]::MaxValue)]
        [int]$MinimumCpuSpeedMHz
    )
    Write-Verbose "Starting $($MyInvocation.MyCommand.Name) for $($PSBoundParameters.Keys -join ', ')"

    $device = Get-IslDeviceFact
    $checks = [System.Collections.Generic.List[object]]::new()

    function Get-Check {
        param([string]$Requirement, [bool]$Met, $Actual, $Expected, [string]$Details, $Code)
        [pscustomobject]@{
            PSTypeName    = 'IntuneScriptLab.RequirementCheck'
            Requirement   = $Requirement
            Met           = $Met
            Actual        = $Actual
            Expected      = $Expected
            Details       = if ($Met) { '' } else { $Details }
            Applicability = if ($Met) { $null } else { $Code }
        }
    }

    if ($Architecture) {
        $checkSplat = @{
            Requirement = 'Architecture'
            Met         = $device.Architecture -in $Architecture
            Actual      = $device.Architecture
            Expected    = $Architecture -join ', '
            Code        = 1000
            Details     = 'Device architecture (e.g. x86/amd64) is not applicable for the application.'
        }
        $checks.Add((Get-Check @checkSplat))
    }
    if ($MinimumWindowsRelease) {
        $required = Get-IslWindowsReleaseBuild -Release $MinimumWindowsRelease
        $checkSplat = @{
            Requirement = 'MinimumWindowsRelease'
            Met         = $device.Build -ge $required
            Actual      = "build $($device.Build)"
            Expected    = "$MinimumWindowsRelease (build $required)"
            Code        = $null
            Details     = ('The operating system release is below the configured minimum (portal text and ' +
                'device code not observed)')
        }
        $checks.Add((Get-Check @checkSplat))
    }
    if ($MinimumFreeDiskSpaceMB) {
        $checkSplat = @{
            Requirement = 'MinimumFreeDiskSpaceMB'
            Met         = $device.FreeDiskSpaceMB -ge $MinimumFreeDiskSpaceMB
            Actual      = $device.FreeDiskSpaceMB
            Expected    = $MinimumFreeDiskSpaceMB
            Code        = 1001
            Details     = 'Available disk space on the target device is less than the configured minimum.'
        }
        $checks.Add((Get-Check @checkSplat))
    }
    if ($MinimumMemoryMB) {
        $checkSplat = @{
            Requirement = 'MinimumMemoryMB'
            Met         = $device.MemoryMB -ge $MinimumMemoryMB
            Actual      = $device.MemoryMB
            Expected    = $MinimumMemoryMB
            Code        = 1003
            Details     = 'Amount of RAM on the target device is less than the configured minimum.'
        }
        $checks.Add((Get-Check @checkSplat))
    }
    if ($MinimumProcessors) {
        $checkSplat = @{
            Requirement = 'MinimumProcessors'
            Met         = $device.Processors -ge $MinimumProcessors
            Actual      = $device.Processors
            Expected    = $MinimumProcessors
            Code        = 1004
            Details     = 'Count of logical processors on the target device is less than the configured minimum.'
        }
        $checks.Add((Get-Check @checkSplat))
    }
    if ($MinimumCpuSpeedMHz) {
        $checkSplat = @{
            Requirement = 'MinimumCpuSpeedMHz'
            Met         = $device.CpuSpeedMHz -ge $MinimumCpuSpeedMHz
            Actual      = $device.CpuSpeedMHz
            Expected    = $MinimumCpuSpeedMHz
            Code        = $null
            Details     = ('The CPU speed is below the configured minimum (portal text and device code not ' +
                'observed)')
        }
        $checks.Add((Get-Check @checkSplat))
    }

    $failed = @($checks | Where-Object { -not $_.Met })
    $first = if ($failed.Count) { $failed[0] } else { $null }
    Write-Verbose "Completed $($MyInvocation.MyCommand.Name): $($checks.Count) checks, $($failed.Count) failed"
    [pscustomobject]@{
        PSTypeName    = 'IntuneScriptLab.ApplicabilityResult'
        Applicable    = ($failed.Count -eq 0)
        Details       = if ($first) { $first.Details } else { '' }
        Applicability = if ($first) { $first.Applicability } else { 0 }
        Reason        = if ($first) {
            "$($first.Requirement): $($first.Actual) against $($first.Expected); Intune reports Not applicable"
        }
        else { "Every requirement is met ($($checks.Count) checked); the detection runs next" }
        Checks        = $checks.ToArray()
    }
}
