function Get-IslWindowsReleaseBuild {
    <#
    .SYNOPSIS
        Maps a Windows release name, as the Graph minimumSupportedWindowsRelease values name it, to its build.

    .DESCRIPTION
        The portal's "Minimum operating system" list is stored as a release name; the agent compares
        builds. This is the Windows 10 and 11 release-to-build table.

    .PARAMETER Release
        1607 to 22H2 (Windows 10) or Windows11_21H2 to Windows11_25H2.

    .EXAMPLE
        Get-IslWindowsReleaseBuild -Release Windows11_24H2

        26100
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string]$Release
    )

    $builds = @{
        '1607'           = 14393
        '1703'           = 15063
        '1709'           = 16299
        '1803'           = 17134
        '1809'           = 17763
        '1903'           = 18362
        '1909'           = 18363
        '2004'           = 19041
        '20H2'           = 19042
        '21H1'           = 19043
        '21H2'           = 19044
        '22H2'           = 19045
        'Windows11_21H2' = 22000
        'Windows11_22H2' = 22621
        'Windows11_23H2' = 22631
        'Windows11_24H2' = 26100
        'Windows11_25H2' = 26200
    }
    if (-not $builds.ContainsKey($Release)) { throw "Unknown Windows release '$Release'" }
    $builds[$Release]
}
