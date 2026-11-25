function Get-IslWindowsReleaseBuild {
    <#
    .SYNOPSIS
        Maps a Windows release name, as Graph writes it, to its build number.

    .DESCRIPTION
        The portal's "Minimum operating system" list is stored as a release name; the agent compares
        builds. This is the Windows 10 and 11 release-to-build table.

    .PARAMETER Release
        1607 to 22H2 (Windows 10) or Windows11_21H2 to Windows11_25H2.

    .EXAMPLE
        Get-IslWindowsReleaseBuild -Release Windows11_24H2

        26100

    .INPUTS
        None.

    .OUTPUTS
        System.Int32.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string]$Release
    )

    # The table is Data\WindowsReleaseBuilds.psd1, read when the module is imported
    $builds = $script:IslWindowsReleaseBuilds
    if (-not $builds.ContainsKey($Release)) {
        $recordSplat = @{
            Message = "Unknown Windows release '$Release'"
            ErrorId = 'WindowsReleaseUnknown'
            Category = [System.Management.Automation.ErrorCategory]::InvalidArgument
            TargetObject = $Release
            ExceptionType = [System.ArgumentException]
        }
        $PSCmdlet.ThrowTerminatingError((New-IslErrorRecord @recordSplat))
    }
    $builds[$Release]
}
