#Requires -Version 5.1

<#
    .SYNOPSIS
        Gives a lab device a local D: volume and an X: drive mapped in the user's session.

    .DESCRIPTION
        The fixture REM-DRIVES-SYS looks at (Findings, "PowerShell 7 at run time, a built
        credential, and the drives SYSTEM sees"). Run on the device as SYSTEM through the guest
        agent:

            .\Invoke-LabGuestScript.ps1 -VmId 125 -ScriptPath .\New-IslDriveFixture.ps1

        D: is a 64 MB virtual disk under C:\ProgramData\IntuneScriptLab, attached and formatted
        with diskpart; it is detached by a restart and attached again by another run. X: is a
        share of a folder beside it, mapped with "net use" by a scheduled task that runs inside the
        console user's own session, which is the only place a user's mapped drive exists. Every
        step is skipped when it is already done, because a guest exec retried after a host-side
        timeout runs the script twice.

    .PARAMETER UserName
        The signed-in account whose session gets the mapping. Default: the owner of explorer.exe.

    .PARAMETER Remove
        Undo the fixture: unmap X:, remove the share and the task, detach and delete the disk.

    .EXAMPLE
        .\Invoke-LabGuestScript.ps1 -VmId 125 -ScriptPath .\New-IslDriveFixture.ps1

        Creates the fixture on VM 125 and prints what the user's session and SYSTEM each see.

    .EXAMPLE
        .\Invoke-LabGuestScript.ps1 -VmId 125 -ScriptPath .\New-IslDriveFixture.ps1 -ArgumentList '-Remove'

        Removes it again.

    .EXAMPLE
        .\New-IslDriveFixture.ps1 -UserName isl-user

        On the device itself, elevated, naming the account instead of reading it from explorer.exe.

    .INPUTS
        None.

    .OUTPUTS
        System.String. What "net use" shows inside the user's session, then the drives SYSTEM sees.

    .NOTES
        Author: Jeffrey Stuhr. Needs SYSTEM or an elevated session, and a signed-in console user.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$UserName,

    [switch]$Remove
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$lab = 'C:\ProgramData\IntuneScriptLab'
$disk = Join-Path -Path $lab -ChildPath 'isl-d.vhdx'
$shareFolder = Join-Path -Path $lab -ChildPath 'Share'
$shareName = 'isl-share'
$taskName = 'ISL-MapDrive'
$report = Join-Path -Path $lab -ChildPath 'mapdrive.txt'


function Invoke-DiskPart {
    <#
    .SYNOPSIS
    Runs diskpart commands from a script file and returns its result lines.

    .DESCRIPTION
    Writes the commands to diskpart.txt in the lab folder as ASCII, runs diskpart.exe /s on it,
    removes the file again and returns only the lines that report success, an error or a failure.

    .PARAMETER Command
    The diskpart commands, one for each line of the script file.

    .EXAMPLE
    Invoke-DiskPart -Command "select vdisk file=$disk", 'attach vdisk'

    Attaches the fixture's virtual disk.

    .INPUTS
    None.

    .OUTPUTS
    System.String. The lines of diskpart's output that mention success, an error or a failure.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string[]]$Command
    )

    $scriptFile = Join-Path -Path $lab -ChildPath 'diskpart.txt'
    Set-Content -LiteralPath $scriptFile -Value $Command -Encoding ASCII
    $output = & diskpart.exe /s $scriptFile 2>&1
    Remove-Item -LiteralPath $scriptFile -ErrorAction SilentlyContinue
    $output | Where-Object { $_ -match 'success|error|fail' }
}


function Invoke-InUserSession {
    <#
    .SYNOPSIS
    Runs a cmd.exe command line inside a signed-in account's own logon session.

    .DESCRIPTION
    A one-shot task with an Interactive principal runs inside the account's own logon session.
    The task runs cmd.exe with the command line, its output redirected to the report file, and is
    removed again after six seconds. The non-empty lines of the report are returned.

    .PARAMETER Account
    The signed-in account whose session runs the command line.

    .PARAMETER CommandLine
    The cmd.exe command line to run, such as "net use".

    .EXAMPLE
    Invoke-InUserSession -Account 'isl-user' -CommandLine 'net use & whoami'

    Lists the drives mapped in the user's session and the identity that ran the command.

    .INPUTS
    None.

    .OUTPUTS
    System.String. The non-empty lines the command line wrote.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Account,

        [Parameter(Mandatory)]
        [string]$CommandLine
    )

    if (Test-Path -LiteralPath $report) { Clear-Content -LiteralPath $report }
    $action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument "/c ($CommandLine) > `"$report`" 2>&1"
    $principal = New-ScheduledTaskPrincipal -UserId $Account -LogonType Interactive -RunLevel Limited
    $null = Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Force
    Start-ScheduledTask -TaskName $taskName
    Start-Sleep -Seconds 6
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Get-Content -LiteralPath $report -ErrorAction SilentlyContinue | Where-Object { "$_".Trim() }
}


if (-not $UserName) {
    $shell = Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe'" | Select-Object -First 1
    if ($shell) {
        # GetOwner only reads, but Invoke-CimMethod asks ShouldProcess for any method: under -WhatIf
        # it would return nothing, and the script would end with no signed-in user
        $ownerSplat = @{ InputObject = $shell; MethodName = 'GetOwner'; WhatIf = $false; Confirm = $false }
        $UserName = (Invoke-CimMethod @ownerSplat).User
    }
}
if (-not $UserName) { throw 'No signed-in user found (no explorer.exe); pass -UserName.' }

if ($Remove) {
    if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Remove the D: and X: fixture')) {
        Invoke-InUserSession -Account $UserName -CommandLine 'net use X: /delete /y & net use'
        if (Get-SmbShare -Name $shareName -ErrorAction SilentlyContinue) {
            Remove-SmbShare -Name $shareName -Force
        }
        if (Test-Path -LiteralPath $disk) {
            Invoke-DiskPart -Command "select vdisk file=$disk", 'detach vdisk'
            Remove-Item -LiteralPath $disk -Force
        }
        Remove-Item -LiteralPath $shareFolder -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $report -ErrorAction SilentlyContinue
    }
}
elseif ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Create D: and map X: for $UserName")) {
    $null = New-Item -ItemType Directory -Path $shareFolder -Force
    if (-not (Test-Path -LiteralPath 'D:\')) {
        if (Test-Path -LiteralPath $disk) { Invoke-DiskPart -Command "select vdisk file=$disk", 'attach vdisk' }
        else {
            $create = "create vdisk file=$disk maximum=64 type=expandable", 'attach vdisk',
            'create partition primary', 'format fs=ntfs quick label=ISLLOCAL', 'assign letter=D'
            Invoke-DiskPart -Command $create
        }
    }
    # ASCII writes the bytes that the default encoding of both Windows PowerShell 5.1 and
    # PowerShell 7 wrote for this text
    Set-Content -LiteralPath (Join-Path -Path $shareFolder -ChildPath 'hello.txt') -Value 'mapped' -Encoding ASCII
    if (-not (Get-SmbShare -Name $shareName -ErrorAction SilentlyContinue)) {
        $null = New-SmbShare -Name $shareName -Path $shareFolder -ReadAccess 'Everyone'
    }
    "--- as $UserName ---"
    $map = "if not exist X:\hello.txt net use X: \\localhost\$shareName /persistent:no"
    Invoke-InUserSession -Account $UserName -CommandLine "$map & net use & whoami"
}

"--- as $([Security.Principal.WindowsIdentity]::GetCurrent().Name) ---"
$drives = [IO.DriveInfo]::GetDrives() | ForEach-Object { "$($_.Name)=$($_.DriveType)" }
"drives=$($drives -join ',') X=[$(Test-Path -LiteralPath 'X:\')]"
