function Get-IslDsregStatus {
    <#
    .SYNOPSIS
        Returns the lines of dsregcmd /status, or nothing where the tool is missing.

    .DESCRIPTION
        Separated from Get-IslFilterDeviceFact so the join-type mapping can be tested with a fixed
        status text. dsregcmd ships with Windows 10 and later.

    .EXAMPLE
        Get-IslDsregStatus | Select-String 'AzureAdJoined'

        The join line of this device.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    if (-not (Get-Command -Name dsregcmd.exe -ErrorAction SilentlyContinue)) { return @() }
    @(& dsregcmd.exe /status 2>$null | ForEach-Object { "$_" })
}
