#Requires -Version 7.6

<#
.SYNOPSIS
    Creates a disposable Windows test VM on Proxmox for IntuneScriptLab validation runs.

.DESCRIPTION
    Linked-clones a sysprepped Windows template, waits for the first-boot pass to settle at the
    OOBE account screen, re-enables the online (work or school) account screens that an unattend
    may have hidden, reboots back into OOBE and snapshots the VM as "clean-oobe".

    Joining the device is deliberately left to a person: Entra join needs a user sign-in with MFA.
    After the join, snapshot again (see Validation\README.md) so the enrolled state can be restored
    with `qm rollback`.

    Talks to the Proxmox host over SSH (key-based) and to the guest through the QEMU guest agent,
    which the template must have installed.

.EXAMPLE
    .\New-IntuneLabVm.ps1 -TemplateId 123 -VmId 126 -Name INTUNE-TEST-03
#>
[CmdletBinding(SupportsShouldProcess)]
# TimeoutMinutes is read inside Wait-GuestAtOobe; the analyzer can't see that
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'TimeoutMinutes')]
param(
    [Parameter(Mandatory)][int]$TemplateId,
    [Parameter(Mandatory)][int]$VmId,
    [Parameter(Mandatory)][string]$Name,
    [string]$ProxmoxHost = 'pve',
    [string]$Tags = 'intune-test',
    [int]$TimeoutMinutes = 20,
    # Skip the registry change that re-enables the work-or-school sign-in at OOBE
    [switch]$KeepOobeAccountScreens
)

$ErrorActionPreference = 'Stop'

function Invoke-Qm {
    param([Parameter(Mandatory)][string]$Command)
    $out = ssh -o BatchMode=yes $ProxmoxHost $Command 2>&1
    if ($LASTEXITCODE -ne 0) { throw "ssh ${ProxmoxHost}: '$Command' failed: $out" }
    $out
}

function Invoke-Guest {
    # Runs PowerShell inside the VM via the guest agent; returns stdout or $null if the agent isn't up.
    param([Parameter(Mandatory)][string]$Script)
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Script))
    $raw = ssh -o BatchMode=yes $ProxmoxHost ("qm guest exec $VmId --timeout 60 -- powershell -NoProfile " +
        "-NonInteractive -EncodedCommand $encoded") 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $raw) { return $null }
    (($raw -join "`n") | ConvertFrom-Json).'out-data'
}

function Wait-GuestAtOobe {
    # The first boot after sysprep reboots at least once; "settled" = OOBE flag cleared and the
    # defaultuser0 setup session is active.
    param([Parameter(Mandatory)][string]$Because)
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $waitMessage = "Waiting for VM $VmId to reach the OOBE account screen ($Because)..."
    Write-Information -InformationAction Continue -MessageData $waitMessage
    do {
        Start-Sleep -Seconds 20
        $state = Invoke-Guest -Script @'
$oobe = (Get-ItemProperty HKLM:\SYSTEM\Setup -ErrorAction SilentlyContinue).OOBEInProgress
$session = (quser 2>$null) -match 'defaultuser0'
"$oobe|$([bool]$session)"
'@
        if ($state -and $state.Trim() -eq '0|True') { return }
    } while ((Get-Date) -lt $deadline)
    throw "VM $VmId did not reach the OOBE account screen within $TimeoutMinutes minutes"
}

if (-not $PSCmdlet.ShouldProcess("VM $VmId ($Name) from template $TemplateId on " +
    "$ProxmoxHost", 'Create')) { return }

Write-Information -InformationAction Continue -MessageData "Cloning template $TemplateId to VM $VmId ($Name)..."
Invoke-Qm "qm clone $TemplateId $VmId --name $Name" | Out-Null
Invoke-Qm "qm set $VmId --tags $Tags --onboot 0" | Out-Null
Invoke-Qm "qm start $VmId" | Out-Null
Wait-GuestAtOobe -Because 'first boot'

if (-not $KeepOobeAccountScreens) {
    # An unattend with HideOnlineAccountScreens leaves OOBE offering only a local account. The
    # values persist in the registry and OOBE re-reads them on the next boot.
    $rebootMessage = 'Re-enabling online account screens and rebooting into OOBE...'
    Write-Information -InformationAction Continue -MessageData $rebootMessage
    Invoke-Guest -Script @'
$key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE'
Set-ItemProperty -Path $key -Name HideOnlineAccountScreens -Value 0
Set-ItemProperty -Path $key -Name HideLocalAccountScreen -Value 0
shutdown /r /t 3
'@ | Out-Null
    Start-Sleep -Seconds 30
    Wait-GuestAtOobe -Because 'after OOBE fix'
}

Invoke-Qm ("qm snapshot $VmId clean-oobe --description 'Settled at OOBE before any join. Created by " +
    "New-IntuneLabVm.ps1'") | Out-Null
$info = Invoke-Guest -Script ('"$env:COMPUTERNAME|" + ((Get-NetIPAddress -AddressFamily IPv4 | Where-Object ' +
    'IPAddress -notlike "127.*").IPAddress -join ",")')
$hostname, $ip = ($info.Trim() -split '\|')

[pscustomobject]@{
    VmId     = $VmId
    Name     = $Name
    Hostname = $hostname
    IPv4     = $ip
    Snapshot = 'clean-oobe'
    NextStep = 'Open the console, choose "Set up for work or school", sign in, then snapshot as "joined".'
}
