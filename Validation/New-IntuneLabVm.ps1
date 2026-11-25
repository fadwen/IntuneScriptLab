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

.PARAMETER TemplateId
    The Proxmox id of the sysprepped Windows template to clone.

.PARAMETER VmId
    The Proxmox id the new VM gets. It must not be in use.

.PARAMETER Name
    The name the new VM gets in Proxmox.

.PARAMETER ProxmoxHost
    The SSH host name of the Proxmox node, reached with key-based authentication. Default pve.

.PARAMETER Tags
    The Proxmox tags set on the new VM. Default intune-test.

.PARAMETER TimeoutMinutes
    How long each wait for the guest to settle at the OOBE account screen may take. Default 20.

.PARAMETER KeepOobeAccountScreens
    Skip the registry change that re-enables the work-or-school sign-in at OOBE, and the reboot
    that follows it.

.EXAMPLE
    .\New-IntuneLabVm.ps1 -TemplateId 123 -VmId 126 -Name INTUNE-TEST-03

    Clones template 123 to VM 126, settles it at OOBE and snapshots it as clean-oobe.

.INPUTS
    None.

.OUTPUTS
    IntuneScriptLab.Validation.LabVm. The VM id, name, the guest's host name and IPv4 addresses,
    the snapshot taken and the step left to a person.
#>
[CmdletBinding(SupportsShouldProcess)]
# TimeoutMinutes is read inside Wait-GuestAtOobe; the analyzer can't see that
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'TimeoutMinutes')]
[OutputType('IntuneScriptLab.Validation.LabVm')]
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

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'


function Invoke-Qm {
    <#
    .SYNOPSIS
    Runs a command on the Proxmox host over SSH and returns its output.

    .DESCRIPTION
    Runs the command with ssh in batch mode, so that a missing key fails instead of prompting, on
    the host that the script's -ProxmoxHost names. The output includes what ssh and the command
    wrote to the error stream. A non-zero exit code ends the function with an error that carries
    the command and its output.

    .PARAMETER Command
    The command line to run on the Proxmox host, such as "qm start 126".

    .EXAMPLE
    Invoke-Qm -Command "qm start $VmId"

    Starts the VM on the Proxmox host.

    .INPUTS
    None.

    .OUTPUTS
    System.String. The lines the command wrote.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Command
    )

    $out = ssh -o BatchMode=yes $ProxmoxHost $Command 2>&1
    if ($LASTEXITCODE -ne 0) {
        $exception = [System.InvalidOperationException]::new("ssh ${ProxmoxHost}: '$Command' failed: $out")
        $category = [System.Management.Automation.ErrorCategory]::InvalidResult
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception, 'QmCommandFailed', $category, $Command)
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }
    $out
}


# The guest agent calls are GuestAgent.ps1's; Invoke-GuestPowerShell reads $ProxmoxHost and $VmId
# from this scope
. (Join-Path -Path $PSScriptRoot -ChildPath 'GuestAgent.ps1')


function Invoke-Guest {
    <#
    .SYNOPSIS
    Runs PowerShell inside the VM, or returns nothing while its agent is not up.

    .DESCRIPTION
    Runs the script through the QEMU guest agent with Invoke-GuestPowerShell from GuestAgent.ps1,
    with a timeout of 60 seconds and its warnings silenced. Any failure returns $null instead of an
    error, because the agent is unreachable while the guest reboots, and the OOBE wait polls on
    that.

    .PARAMETER Script
    The PowerShell text to run in the guest.

    .EXAMPLE
    Invoke-Guest -Script '$env:COMPUTERNAME'

    Returns the guest's computer name, or $null when the agent does not answer.

    .INPUTS
    None.

    .OUTPUTS
    System.String. What the script wrote in the guest.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Script
    )

    try {
        Invoke-GuestPowerShell -Script $Script -TimeoutSeconds 60 -WarningAction SilentlyContinue
    } catch {
        # Expected while the guest reboots or the agent has not started: the caller polls on $null
        $null
    }
}


function Wait-GuestAtOobe {
    <#
    .SYNOPSIS
    Waits until the VM has settled at the OOBE account screen.

    .DESCRIPTION
    The first boot after sysprep reboots at least once; "settled" = OOBE flag cleared and the
    defaultuser0 setup session is active. Polls the guest every 20 seconds for up to the script's
    -TimeoutMinutes, and ends with an error when the guest has not settled by then.

    .PARAMETER Because
    Why the wait is made, shown in the progress message, such as "first boot".

    .EXAMPLE
    Wait-GuestAtOobe -Because 'first boot'

    Waits for the cloned VM to settle after its first boot.

    .INPUTS
    None.

    .OUTPUTS
    None.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$Because
    )

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
    $message = "VM $VmId did not reach the OOBE account screen within $TimeoutMinutes minutes"
    $exception = [System.TimeoutException]::new($message)
    $category = [System.Management.Automation.ErrorCategory]::OperationTimeout
    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
        $exception, 'OobeWaitTimedOut', $category, $VmId)
    $PSCmdlet.ThrowTerminatingError($errorRecord)
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
    PSTypeName = 'IntuneScriptLab.Validation.LabVm'
    VmId = $VmId
    Name = $Name
    Hostname = $hostname
    IPv4 = $ip
    Snapshot = 'clean-oobe'
    NextStep = 'Open the console, choose "Set up for work or school", sign in, then snapshot as "joined".'
}
