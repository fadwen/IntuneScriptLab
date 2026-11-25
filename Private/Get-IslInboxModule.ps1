function Get-IslInboxModule {
    <#
    .SYNOPSIS
        Lists the modules Windows PowerShell 5.1 loads as SYSTEM on plain Windows 11.

    .DESCRIPTION
        Get-Module -ListAvailable as NT AUTHORITY\SYSTEM on an Entra-joined Windows 11 24H2 test
        device with nothing installed beyond Windows itself (VM 125, 2026-09-28, the same 90 again
        on 2026-10-06 under Windows 11 Enterprise LTSC 24H2): the list a script can import under
        the agent without installing anything first. Feature-on-demand modules (RSAT, Hyper-V,
        containers) are absent on purpose, since a device may or may not have them.

        Microsoft.PowerShell.Core is listed although Get-Module -ListAvailable never shows it: the
        engine's own module, whose commands every session has. Import-Module of it by name fails on
        both hosts ("no valid module file was found", 2026-10-06), which is a script's mistake of
        another kind than a missing module. A Home edition lacks seven of the others
        (AppLocker, AppvClient, AssignedAccess, BranchCache, ConfigCI, iSCSI, UEV), and a Windows 11
        Home ARM64 host has HostNetworkingService in addition; the unit test holds the table against
        the host it runs on with those allowances.

    .EXAMPLE
        'ActiveDirectory' -in (Get-IslInboxModule)

        False: the RSAT module is not there unless the feature was added.

    .INPUTS
        None.

    .OUTPUTS
        System.String.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # The table is Data\InboxModules.psd1, read when the module is imported
    foreach ($module in $script:IslInboxModules) {
        $module
    }
}
