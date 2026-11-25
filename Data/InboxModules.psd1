# The modules Windows PowerShell 5.1 loads as NT AUTHORITY\SYSTEM on an Entra-joined Windows 11 24H2
# device with nothing installed beyond Windows itself (VM 125, 2026-09-28, the same 90 again on
# 2026-10-06 under Windows 11 Enterprise LTSC 24H2). Get-IslInboxModule returns them; its help says
# which modules a Home edition and an ARM64 host lack or add.
@{
    Modules = @(
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
