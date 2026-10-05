#Requires -Version 7.4

<#
    .SYNOPSIS
        Runs a local PowerShell script inside a Proxmox lab VM through the QEMU guest agent, as SYSTEM.

    .DESCRIPTION
        The guest agent's command line fails silently above a few KB, so the script is delivered as
        base64 in numbered part files (Set-Content, so a chunk retried after a host-side timeout
        rewrites the same part rather than appending it twice), joined and decoded on the VM, then
        run with Windows PowerShell under a process-scoped execution policy bypass. Talks to the
        Proxmox host over key-based SSH; the VM needs the guest agent.

    .PARAMETER VmId
        The Proxmox VM id.

    .PARAMETER ScriptPath
        The local script to run.

    .PARAMETER ArgumentList
        Arguments appended to the script call on the VM, for example '-AutoLogon'.

    .PARAMETER ProxmoxHost
        The SSH host name. Default pve.

    .PARAMETER TimeoutSeconds
        How long the guest agent waits for the script. Default 600.

    .PARAMETER RemoteName
        The file name under C:\ProgramData\IntuneScriptLab on the VM. Default: the script's name.

    .EXAMPLE
        .\Invoke-LabGuestScript.ps1 -VmId 125 -ScriptPath .\New-IslHarnessUser.ps1 -ArgumentList '-AutoLogon'

        Creates the harness account on VM 125 and sets its autologon; reboot the VM afterwards.

    .EXAMPLE
        .\Invoke-LabGuestScript.ps1 -VmId 125 -ScriptPath .\collect.ps1 -TimeoutSeconds 900

        A longer-running collection script.

    .EXAMPLE
        .\Invoke-LabGuestScript.ps1 -VmId 126 -ScriptPath .\Probe.ps1 -RemoteName probe-run.ps1

        The same script under another remote name, so an earlier copy is left alone.

    .INPUTS
        None.

    .OUTPUTS
        System.String. The script's stdout on the VM; its stderr and a non-zero exit become warnings.

    .NOTES
        Author: Jeffrey Stuhr. The guest agent calls are GuestAgent.ps1's: each command is started
        once and its result asked for by process id, so a status call that times out is asked
        again without running the script a second time. A start call that times out is retried and
        can run it twice.
#>
[CmdletBinding()]
# ProxmoxHost is read inside Invoke-GuestPowerShell (GuestAgent.ps1); the analyzer cannot see that
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ProxmoxHost')]
param(
    [Parameter(Mandatory)]
    [int]$VmId,

    [Parameter(Mandatory)]
    [string]$ScriptPath,

    [string[]]$ArgumentList = @(),

    [string]$ProxmoxHost = 'pve',

    [int]$TimeoutSeconds = 600,

    [string]$RemoteName = (Split-Path -Path $ScriptPath -Leaf)
)

$ErrorActionPreference = 'Stop'

. (Join-Path -Path $PSScriptRoot -ChildPath 'GuestAgent.ps1')

$remote = "C:\ProgramData\IntuneScriptLab\$RemoteName"
$content = Get-Content -Path (Resolve-Path -Path $ScriptPath) -Raw
$b64 = [Convert]::ToBase64String([Text.UTF8Encoding]::new($true).GetPreamble() +
    [Text.Encoding]::UTF8.GetBytes($content))
$null = Invoke-GuestPowerShell -Script ("New-Item -ItemType Directory -Path 'C:\ProgramData\IntuneScriptLab' " +
    "-Force | Out-Null; Remove-Item -Path '$remote.b64.*' -ErrorAction SilentlyContinue")
$index = 0
for ($offset = 0; $offset -lt $b64.Length; $offset += 1200) {
    $part = $b64.Substring($offset, [Math]::Min(1200, $b64.Length - $offset))
    $partPath = '{0}.b64.{1:D4}' -f $remote, $index++
    $null = Invoke-GuestPowerShell -Script "Set-Content -Path '$partPath' -Value '$part' -NoNewline"
}
$deliveredMessage = "Delivered $ScriptPath to VM $VmId as $remote ($index parts)"
Write-Information -InformationAction Continue -MessageData $deliveredMessage

$decode = "`$parts = Get-ChildItem -Path '$remote.b64.*' | Sort-Object Name | " +
    "ForEach-Object { Get-Content -Path `$_.FullName -Raw }; " +
    "[IO.File]::WriteAllBytes('$remote', [Convert]::FromBase64String((-join `$parts)))"
# A parameter name (-AutoLogon) must reach the script bare, or it binds as a positional string;
# only values with spaces or quotes are quoted
$arguments = ($ArgumentList | ForEach-Object {
        if ($_ -match '^-[A-Za-z]' -or $_ -notmatch "[\s']") { $_ } else { "'$($_ -replace "'", "''")'" }
    }) -join ' '
Invoke-GuestPowerShell -TimeoutSeconds $TimeoutSeconds -Script (
    "$decode; Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force; & '$remote' $arguments")
