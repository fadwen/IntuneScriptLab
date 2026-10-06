function Get-IslInboxModule {
    <#
    .SYNOPSIS
        The modules Windows PowerShell 5.1 can load as SYSTEM on a plain Windows 11 device.

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
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    @(
        'AppBackgroundTask', 'AppLocker', 'AppvClient', 'Appx', 'AssignedAccess', 'BitLocker', 'BitsTransfer',
        'BranchCache', 'CimCmdlets', 'ConfigCI', 'ConfigDefender', 'ConfigDefenderPerformance', 'Defender',
        'DefenderPerformance', 'DeliveryOptimization', 'DirectAccessClientComponents', 'Dism', 'DnsClient',
        'EventTracingManagement', 'Get-NetView', 'International', 'iSCSI', 'ISE', 'Kds', 'LanguagePackManagement',
        'LAPS', 'Microsoft.PowerShell.Archive', 'Microsoft.PowerShell.Diagnostics', 'Microsoft.PowerShell.Host',
        'Microsoft.PowerShell.LocalAccounts', 'Microsoft.PowerShell.Management', 'Microsoft.PowerShell.ODataUtils',
        'Microsoft.PowerShell.Operation.Validation', 'Microsoft.PowerShell.Security',
        'Microsoft.PowerShell.Utility', 'Microsoft.PowerShell.Core', 'Microsoft.ReFsDedup.Commands',
        'Microsoft.Windows.Bcd.Cmdlets', 'Microsoft.WSMan.Management', 'MMAgent', 'MsDtc', 'NetAdapter',
        'NetConnection', 'NetEventPacketCapture', 'NetLbfo', 'NetNat', 'NetQos', 'NetSecurity', 'NetSwitchTeam',
        'NetTCPIP', 'NetworkConnectivityStatus', 'NetworkSwitchManager', 'NetworkTransition', 'OsConfiguration',
        'OSLicense', 'PackageManagement', 'PcsvDevice', 'PersistentMemory', 'Pester', 'PKI', 'PnpDevice',
        'PowerShellGet', 'PrintManagement', 'ProcessMitigations', 'Provisioning', 'PSDesiredStateConfiguration',
        'PSDiagnostics', 'PSReadLine', 'PSScheduledJob', 'PSWorkflow', 'PSWorkflowUtility', 'ScheduledTasks',
        'SecureBoot', 'SmbShare', 'SmbWitness', 'StartLayout', 'Storage', 'StorageBusCache', 'TLS',
        'TroubleshootingPack', 'TrustedPlatformModule', 'UEV', 'VMDirectStorage', 'VpnClient', 'Wdac', 'Whea',
        'WindowsDeveloperLicense', 'WindowsErrorReporting', 'WindowsSearch', 'WindowsUpdate', 'WinHttpProxy'
    )
}
