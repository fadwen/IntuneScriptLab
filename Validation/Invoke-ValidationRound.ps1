#Requires -Version 7.6
#Requires -Modules Microsoft.Graph.Authentication

<#
.SYNOPSIS
    Runs one step of a validation round against the lab tenant and a test VM.

.DESCRIPTION
    Deploys IntuneScriptLab validation experiments to a test device, triggers them, and collects
    what both Intune and the device recorded.

    Each experiment in Experiments.psd1 becomes an Intune remediation or platform script named
    ISL-<Name>, with Probe.ps1 prepended. Probes write ground truth to C:\ProgramData\IntuneScriptLab
    on the device; Collect pairs that with Intune's run states so the two can be compared.

    Device-side steps (Trigger, Collect) run through the QEMU guest agent on a Proxmox host over SSH.

.PARAMETER Action
    Prepare  Create C:\ProgramData\IntuneScriptLab on the VM with write access for users, so user-context
             probes can record alongside SYSTEM ones, then run Fixtures.ps1 there (the files, registry
             keys and MSI survey the file/registry/MSI rule experiments rely on). Run once per device.
    Deploy   Create the group, policies and assignments (existing ISL- policies are skipped).
    Trigger  Restart the Intune Management Extension on the VM so it fetches policy now.
    Collect  Write Intune run states and device probe records to Results\.
    Remove   Delete all ISL- policies and the validation group.

.PARAMETER TenantId
    Entra tenant id for the app-only Graph connection. Deploy, Collect and Remove need it, with ClientId
    and CertificateThumbprint, when no Graph session is open.

.PARAMETER ClientId
    Application (client) id of the app registration that the Graph connection signs in as.

.PARAMETER CertificateThumbprint
    Thumbprint of the certificate, in the current user's store, that the app registration authenticates
    with.

.PARAMETER AzureADDeviceId
    Entra deviceId (not object id) of the test device; required for Deploy unless -SkipDeviceMember is
    given.

.PARAMETER Name
    Deploy only the experiments whose Name matches (wildcards), for a round that needs an earlier
    phase to have run first (supersedence: the superseded app must be installed before the new one)

.PARAMETER AppName
    Collect: only the Win32 apps whose experiment name matches (wildcards), since each app costs an
    install-status export job of 20-30 seconds

.PARAMETER Since
    Collect: only the probe records written at or after this time (the records of a device that
    has run the hourly experiments for weeks are most of the payload); every record when omitted

.PARAMETER GroupName
    Display name of the Entra security group that the experiments are assigned to. Deploy creates it
    when it does not exist, and Remove deletes it.

.PARAMETER SkipDeviceMember
    Deploy: leave the group's membership alone (a user group for user-targeted experiments)

.PARAMETER ProxmoxHost
    SSH host name of the Proxmox server whose QEMU guest agent runs the device-side steps.

.PARAMETER VmId
    Proxmox id of the test VM.

.PARAMETER ExperimentsPath
    Path of the experiment definitions that Deploy reads.

.PARAMETER ResultsPath
    Folder that Collect writes its round-<timestamp>.json file to; created when it does not exist.

.PARAMETER IntuneWinAppUtilPath
    Microsoft's Win32 Content Prep Tool; needed only when Experiments.psd1 has Win32Apps. It is
    downloaded to this path when missing and run only when it carries a valid Microsoft signature.
    Installers that MSI experiments name are downloaded into the same folder.

.EXAMPLE
    $conn = @{ TenantId = '<tenant>'; ClientId = '<app>'; CertificateThumbprint = '<thumb>' }
    .\Invoke-ValidationRound.ps1 -Action Deploy @conn -AzureADDeviceId '<entra device id>'
    .\Invoke-ValidationRound.ps1 -Action Trigger -ProxmoxHost pve -VmId 124
    .\Invoke-ValidationRound.ps1 -Action Collect @conn -ProxmoxHost pve -VmId 124

    Deploys the experiments to the device, makes its agent fetch them, and later collects what Intune
    and the device recorded into a results file.

.INPUTS
    None. The script takes no pipeline input.

.OUTPUTS
    System.String. Prepare and Trigger write the text that the VM printed, and Collect the path of the
    results file.
#>
[CmdletBinding(SupportsShouldProcess)]
# Script parameters are read inside the action functions; the analyzer can't see that
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Prepare', 'Deploy', 'Trigger', 'Collect', 'Remove')]
    [string]$Action,

    [string]$TenantId,
    [string]$ClientId,
    [string]$CertificateThumbprint,

    [string]$AzureADDeviceId,

    [string[]]$Name,

    [string[]]$AppName,

    [datetime]$Since,

    [string]$GroupName = 'ISL-Validation-Devices',

    [switch]$SkipDeviceMember,

    [string]$ProxmoxHost = 'pve',
    [int]$VmId = 124,
    [string]$ExperimentsPath = (Join-Path -Path $PSScriptRoot -ChildPath 'Experiments.psd1'),
    [string]$ResultsPath = (Join-Path -Path $PSScriptRoot -ChildPath 'Results'),

    [string]$IntuneWinAppUtilPath = (
        Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Tools') -ChildPath 'IntuneWinAppUtil.exe')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$prefix = 'ISL-'
. (Join-Path -Path $PSScriptRoot -ChildPath 'GraphRules.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'GuestAgent.ps1')

function New-ValidationErrorRecord {
    <#
    .SYNOPSIS
        Creates the error record that a function of the validation driver ends with.

    .DESCRIPTION
        Wraps the message in an InvalidOperationException and returns an ErrorRecord with the given
        error ID and category, for $PSCmdlet.ThrowTerminatingError(). It is called in the argument of
        that method, so it does nothing that can fail.

    .PARAMETER Message
        The text of the error.

    .PARAMETER ErrorId
        The ID that names the failure, such as DeviceNotFound.

    .PARAMETER Category
        The error category of the failure.

    .PARAMETER TargetObject
        The object that the failure concerns, or nothing.

    .EXAMPLE
        $errorSplat = @{ Message = 'No device'; ErrorId = 'DeviceNotFound'; Category = 'ObjectNotFound' }
        $PSCmdlet.ThrowTerminatingError((New-ValidationErrorRecord @errorSplat))

        Ends the calling function with an ObjectNotFound error named DeviceNotFound.

    .INPUTS
        None.

    .OUTPUTS
        System.Management.Automation.ErrorRecord. The record to end the calling function with.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates an object in memory and changes no state.')]
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory)]
        [string]$ErrorId,

        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorCategory]$Category,

        [AllowNull()]
        [object]$TargetObject
    )

    $exception = [System.InvalidOperationException]::new($Message)
    [System.Management.Automation.ErrorRecord]::new($exception, $ErrorId, $Category, $TargetObject)
}


function Connect-LabGraph {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph app-only for the actions that call Graph.

    .DESCRIPTION
        Prepare and Trigger work on the VM alone and do not connect, and neither does an action that
        finds a Graph session already open. Otherwise the script's TenantId, ClientId and
        CertificateThumbprint are required, and the function ends with an error when one is missing.

    .EXAMPLE
        Connect-LabGraph

        Connects with the script's parameters when the action needs Graph and no session is open.

    .INPUTS
        None.

    .OUTPUTS
        System.Void. The function writes nothing to the pipeline.
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    param()

    if ($Action -notin 'Trigger', 'Prepare' -and -not (Get-MgContext)) {
        if (-not ($TenantId -and $ClientId -and $CertificateThumbprint)) {
            $errorSplat = @{
                Message = 'TenantId, ClientId and CertificateThumbprint are required for this action.'
                ErrorId = 'GraphConnectionParameterMissing'
                Category = 'InvalidArgument'
            }
            $PSCmdlet.ThrowTerminatingError((New-ValidationErrorRecord @errorSplat))
        }
        $connectSplat = @{
            TenantId = $TenantId; ClientId = $ClientId; CertificateThumbprint = $CertificateThumbprint
        }
        try {
            Connect-MgGraph @connectSplat -NoWelcome
        } catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}


function Get-AllGraphItem {
    <#
    .SYNOPSIS
        Gets every item of a Graph collection, following @odata.nextLink.

    .DESCRIPTION
        Requests the URI and then each page that @odata.nextLink names, until a page has no next link,
        and returns the items of every page's value. A page without items adds nothing.

    .PARAMETER Uri
        The Graph URI of the collection's first page, relative or absolute.

    .EXAMPLE
        Get-AllGraphItem -Uri '/beta/deviceManagement/deviceHealthScripts?$select=id,displayName'

        Gets every remediation policy of the tenant.

    .INPUTS
        None.

    .OUTPUTS
        System.Collections.Hashtable. One item of the collection, as Invoke-MgGraphRequest returns it.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Uri
    )

    $items = [System.Collections.Generic.List[object]]::new()
    $pageUri = $Uri
    try {
        while ($pageUri) {
            $page = Invoke-MgGraphRequest -Method GET -Uri $pageUri
            if ($page['value']) { $items.AddRange([object[]]$page['value']) }
            $pageUri = $page['@odata.nextLink']
        }
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
    $items
}


function Get-Win32InstallStatusReport {
    <#
    .SYNOPSIS
        Gets the per-device install state of one Win32 app from an export job.

    .DESCRIPTION
        Per-device install state for one app, via the reports export job (the admin center's own path;
        mobileApps/{id}/deviceStatuses and getDeviceInstallStatusReport are both gone from beta). The
        report refuses to run without an ApplicationId filter, so it is one job per app, and the jobs
        have to be run one at a time: ten submitted together took the full deadline and two never
        finished, so the service queues them. Collect -AppName keeps a round to its own apps.

        The job is polled every five seconds for up to three minutes. A failed poll is retried with a
        warning; a job that has not completed by then is skipped with a warning and returns nothing.

    .PARAMETER AppId
        The Graph id of the Win32 app.

    .EXAMPLE
        Get-Win32InstallStatusReport -AppId '00000000-0000-0000-0000-000000000000'

        Gets one row for each device that reported an install state for the app.

    .INPUTS
        None.

    .OUTPUTS
        System.Management.Automation.PSObject. One row of the report's CSV.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param(
        [Parameter(Mandatory)]
        [string]$AppId
    )

    $exportJobs = '/beta/deviceManagement/reports/exportJobs'
    $rows = $null
    try {
        $job = Invoke-MgGraphRequest -Method POST -Uri $exportJobs -Body @{
            reportName = 'DeviceInstallStatusByApp'
            filter     = "(ApplicationId eq '$AppId')"
            format     = 'csv'
        }
        $deadline = (Get-Date).AddMinutes(3)
        do {
            Start-Sleep -Seconds 5
            # A dropped connection mid-poll is not a reason to lose the whole collection
            try {
                $job = Invoke-MgGraphRequest -Method GET -Uri "$exportJobs/$($job['id'])"
            } catch {
                Write-Warning "Export job poll failed, retrying: $($_.Exception.Message)"
                Start-Sleep -Seconds 10
            }
        } while ($job['status'] -ne 'completed' -and (Get-Date) -lt $deadline)
        if ($job['status'] -ne 'completed') {
            Write-Warning "Install status export job for app $AppId still $($job['status']); skipping"
            return
        }
        $rows = Read-ExportJobCsv -Url $job['url'] -JobId $job['id']
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
    $rows
}


function Read-ExportJobCsv {
    <#
    .SYNOPSIS
        Downloads a finished export job and returns the rows of its CSV.

    .DESCRIPTION
        Downloads a finished export job (a zip holding one CSV) to the temporary folder and returns its
        rows. The zip is deleted afterwards.

    .PARAMETER Url
        The download address that the completed export job reports.

    .PARAMETER JobId
        The export job's id, which names the downloaded zip.

    .EXAMPLE
        Read-ExportJobCsv -Url $job['url'] -JobId $job['id']

        Gets the rows of a completed export job.

    .INPUTS
        None.

    .OUTPUTS
        System.Management.Automation.PSObject. One row of the CSV.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [Parameter(Mandatory)]
        [string]$JobId
    )

    $zipPath = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath "$JobId.zip"
    $rows = $null
    try {
        Invoke-WebRequest -Uri $Url -OutFile $zipPath
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            $rows = foreach ($entry in $zip.Entries) {
                $reader = [IO.StreamReader]::new($entry.Open())
                $reader.ReadToEnd() | ConvertFrom-Csv
                $reader.Dispose()
            }
        } finally {
            $zip.Dispose()
            Remove-Item -LiteralPath $zipPath -ErrorAction SilentlyContinue -WhatIf:$false -Confirm:$false
        }
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
    $rows
}


function ConvertTo-ScriptContent {
    <#
    .SYNOPSIS
        Encodes an experiment script with the probe header for upload to Intune.

    .DESCRIPTION
        Probe header + experiment body, as base64 of UTF-8 bytes with or without a BOM. PadKB appends
        that many kilobytes of comment lines, for the size-limit experiments. Probe.ps1 is read from
        the script's folder, and the parts are joined with CRLF.

    .PARAMETER Body
        The experiment's script text, which follows the probe header.

    .PARAMETER Bom
        Starts the bytes with the UTF-8 byte order mark.

    .PARAMETER PadKB
        Kilobytes of comment lines to append; none when 0 or omitted.

    .EXAMPLE
        ConvertTo-ScriptContent -Body 'exit 0' -Bom

        Encodes a script that exits 0, with a byte order mark.

    .INPUTS
        None.

    .OUTPUTS
        IntuneScriptLab.Validation.ScriptContent. An object with the Base64 text and the Sha256 of the
        bytes.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.Validation.ScriptContent')]
    param(
        [Parameter(Mandatory)]
        [string]$Body,

        [switch]$Bom,

        [int]$PadKB
    )

    $probePath = Join-Path -Path $PSScriptRoot -ChildPath 'Probe.ps1'
    try {
        $probeText = Get-Content -LiteralPath $probePath -Raw
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
    $text = $probeText + "`r`n" + $Body + "`r`n"
    if ($PadKB -gt 0) {
        $line = '# ' + ('pad' * 33) + "`r`n"
        $text += $line * [int][Math]::Ceiling($PadKB * 1024 / $line.Length)
    }
    $bytes = [Text.UTF8Encoding]::new($Bom.IsPresent).GetPreamble() + [Text.Encoding]::UTF8.GetBytes($text)
    [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.Validation.ScriptContent'
        Base64 = [Convert]::ToBase64String($bytes)
        Sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([byte[]]$bytes))
    }
}


function Expand-GzipText {
    <#
    .SYNOPSIS
        Turns the base64 of gzip of UTF-8 text back into the text.

    .DESCRIPTION
        The collect payload as the device wrote it: base64 of gzip of UTF-8 JSON, back to the JSON text.

    .PARAMETER Base64
        The base64 text of the gzip stream.

    .EXAMPLE
        Expand-GzipText -Base64 $encoded | ConvertFrom-Json

        Unpacks the collect payload and reads its JSON.

    .INPUTS
        None.

    .OUTPUTS
        System.String. The unpacked text.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Base64
    )

    try {
        $packed = [System.IO.MemoryStream]::new([Convert]::FromBase64String($Base64))
        $mode = [System.IO.Compression.CompressionMode]::Decompress
        $gzip = [System.IO.Compression.GZipStream]::new($packed, $mode)
        $plain = [System.IO.MemoryStream]::new()
        try {
            $gzip.CopyTo($plain)
        } finally {
            $gzip.Dispose()
            $packed.Dispose()
        }
        $text = [Text.Encoding]::UTF8.GetString($plain.ToArray())
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
    $text
}


function Invoke-GuestScriptFile {
    <#
    .SYNOPSIS
        Runs a script on the VM from a file, for one too long for a command line.

    .DESCRIPTION
        Runs a script that is too long for the guest agent's command line (a few KB): the script is
        written to the VM through Send-GuestFile and run by path. The guest agent calls themselves
        are in GuestAgent.ps1.

        With -Detach the script is started in the background and its done marker is polled every 15
        seconds; the function ends with an error when the marker has not appeared within the timeout,
        warns with the start of anything the script wrote to stderr, and returns its stdout.

    .PARAMETER Script
        The text of the script to run.

    .PARAMETER TimeoutSeconds
        How long the run may take, in seconds.

    .PARAMETER RemoteName
        The file name of the script under C:\ProgramData\IntuneScriptLab on the VM.

    .PARAMETER Detach
        Start the script detached and poll for its done marker instead of waiting on one call

    .EXAMPLE
        Invoke-GuestScriptFile -Script $fixtures -RemoteName 'fixtures.ps1' -TimeoutSeconds 300

        Runs the fixtures script on the VM and returns what it printed.

    .INPUTS
        None.

    .OUTPUTS
        System.String. What the script wrote to stdout.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Script,

        [int]$TimeoutSeconds = 900,

        [string]$RemoteName = 'collect.ps1',

        [switch]$Detach
    )

    # A path on the VM, which is Windows whatever the host runs, so it is not built with Join-Path
    $remote = "C:\ProgramData\IntuneScriptLab\$RemoteName"
    $bytes = [Text.UTF8Encoding]::new($true).GetPreamble() + [Text.Encoding]::UTF8.GetBytes($Script)
    $output = $null
    try {
        Send-GuestFile -RemotePath $remote -Bytes $bytes
        if (-not $Detach) {
            # The agent's own powershell.exe runs under the machine execution policy, which refuses a
            # script file on a fresh device; the process-scoped bypass is what -File -ExecutionPolicy
            # Bypass would have given
            $output = Invoke-GuestPowerShell -TimeoutSeconds $TimeoutSeconds -Script (
                "Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force; & '$remote'")
        } else {
            # A script that runs for minutes is started detached and watched through a done marker with
            # short calls, so no single guest agent call has to stay open for it; its output is read
            # from a file
            foreach ($suffix in '.out', '.err', '.done', '.started') {
                $clear = "Remove-Item -Path '$remote$suffix' -ErrorAction SilentlyContinue"
                $null = Invoke-GuestPowerShell -Script $clear
            }
            # A runner batch file carries the redirections, so the launch itself has no nested quoting;
            # it is delivered as base64 for the same reason
            $runner = @(
                '@echo off'
                ("powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$remote`" " +
                    "1>`"$remote.out`" 2>`"$remote.err`"")
                "echo done>`"$remote.done`""
            ) -join "`r`n"
            $runnerB64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($runner))
            # A guest call can run twice (GuestAgent.ps1), and a second runner would find the output file
            # held by the first, skip the script and write the done marker at once: the started marker
            # makes a repeated launch a no-op
            $launch = "if (-not (Test-Path -Path '$remote.started')) { " +
                "Set-Content -Path '$remote.started' -Value started; [IO.File]::WriteAllText('$remote.cmd', " +
                "[Text.Encoding]::ASCII.GetString([Convert]::FromBase64String('$runnerB64'))); " +
                "Start-Process -FilePath '$remote.cmd' -WindowStyle Hidden }"
            $null = Invoke-GuestPowerShell -Script $launch
            $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
            do {
                Start-Sleep -Seconds 15
                $done = (Invoke-GuestPowerShell -Script "Test-Path -Path '$remote.done'").Trim()
            } while ($done -ne 'True' -and (Get-Date) -lt $deadline)
            if ($done -ne 'True') {
                $errorSplat = @{
                    Message = "Detached guest script $RemoteName did not finish within $TimeoutSeconds s"
                    ErrorId = 'GuestScriptTimedOut'
                    Category = 'OperationTimeout'
                    TargetObject = $RemoteName
                }
                $PSCmdlet.ThrowTerminatingError((New-ValidationErrorRecord @errorSplat))
            }
            $readErr = "Get-Content -Path '$remote.err' -Raw -ErrorAction SilentlyContinue"
            $errText = Invoke-GuestPowerShell -Script $readErr
            if ($errText -and $errText -notmatch '^\s*$' -and $errText -notmatch 'Preparing modules') {
                $errHead = $errText.Substring(0, [Math]::Min(400, $errText.Length))
                Write-Warning "Detached guest script ${RemoteName}: $errHead"
            }
            $readOut = "Get-Content -Path '$remote.out' -Raw -ErrorAction SilentlyContinue"
            $output = Invoke-GuestPowerShell -Script $readOut
        }
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
    $output
}


function Invoke-Deploy {
    <#
    .SYNOPSIS
        Creates the validation group, the experiments' policies and their assignments.

    .DESCRIPTION
        Reads the experiments, finds or creates the validation group and adds the test device to it
        (unless -SkipDeviceMember), then creates and assigns a remediation for each Remediations entry
        and a platform script for each PlatformScripts entry. A policy whose ISL- name already exists is
        skipped. Win32Apps entries are passed to Invoke-DeployWin32. Every creation asks ShouldProcess.

    .EXAMPLE
        Invoke-Deploy -WhatIf

        Shows what the round would create without creating it.

    .INPUTS
        None.

    .OUTPUTS
        System.Void. The function reports what it created on the information stream.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.Void])]
    param()

    if (-not $AzureADDeviceId -and -not $SkipDeviceMember) {
        $errorSplat = @{
            Message = 'AzureADDeviceId is required for Deploy.'
            ErrorId = 'AzureADDeviceIdMissing'
            Category = 'InvalidArgument'
        }
        $PSCmdlet.ThrowTerminatingError((New-ValidationErrorRecord @errorSplat))
    }
    try {
        $experiments = Import-PowerShellDataFile -LiteralPath $ExperimentsPath
        if ($Name) {
            foreach ($kind in 'Remediations', 'PlatformScripts', 'Win32Apps') {
                $experiments[$kind] = @($experiments[$kind] | Where-Object {
                        $candidate = $_['Name']
                        @($Name | Where-Object { $candidate -like $_ }).Count -gt 0
                    })
            }
        }

        # Group containing just the test device
        $groupQuery = "/v1.0/groups?`$filter=displayName eq '$GroupName'"
        $group = (Invoke-MgGraphRequest -Method GET -Uri $groupQuery)['value'] | Select-Object -First 1
        if (-not $group -and $PSCmdlet.ShouldProcess($GroupName, 'Create group')) {
            $group = Invoke-MgGraphRequest -Method POST -Uri '/v1.0/groups' -Body @{
                displayName     = $GroupName
                mailEnabled     = $false
                mailNickname    = ($GroupName -replace '[^A-Za-z0-9]', '')
                securityEnabled = $true
                description     = 'IntuneScriptLab validation target. Safe to delete.'
            }
        }
        # No group when -WhatIf declined to create it
        $groupId = if ($group) { $group['id'] } else { $null }
        if ($SkipDeviceMember) {
            $device = $null
        } else {
            $deviceQuery = "/v1.0/devices?`$filter=deviceId eq '$AzureADDeviceId'&`$select=id,displayName"
            $device = (Invoke-MgGraphRequest -Method GET -Uri $deviceQuery)['value'] | Select-Object -First 1
        }
        if (-not $device -and -not $SkipDeviceMember) {
            $errorSplat = @{
                Message = "No Entra device with deviceId $AzureADDeviceId"
                ErrorId = 'DeviceNotFound'
                Category = 'ObjectNotFound'
                TargetObject = $AzureADDeviceId
            }
            $PSCmdlet.ThrowTerminatingError((New-ValidationErrorRecord @errorSplat))
        }
        # A just-created group can 404 for a few seconds while Entra replicates it. Under -WhatIf
        # there is no group to add the device to, and the rehearsal goes on to the policies
        for ($attempt = 1; $device -and $groupId; $attempt++) {
            try {
                $memberReply = Invoke-MgGraphRequest -Method GET -Uri "/v1.0/groups/$groupId/members?`$select=id"
                $members = @($memberReply['value'] | ForEach-Object { $_['id'] })
                $deviceObjectId = $device['id']
                if ($deviceObjectId -notin $members -and $PSCmdlet.ShouldProcess($device['displayName'],
                        "Add to $GroupName")) {
                    Invoke-MgGraphRequest -Method POST -Uri "/v1.0/groups/$groupId/members/`$ref" -Body @{
                        '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$deviceObjectId"
                    }
                }
                break
            } catch {
                if ($attempt -ge 6) {
                    $PSCmdlet.ThrowTerminatingError($_)
                }
                Write-Verbose "Group not ready (attempt $attempt): $($_.Exception.Message)"
                Start-Sleep -Seconds 10
            }
        }
        $target = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $groupId }

        $remediationQuery = '/beta/deviceManagement/deviceHealthScripts?$select=id,displayName'
        $existingRem = @(Get-AllGraphItem -Uri $remediationQuery | ForEach-Object { $_['displayName'] })
        foreach ($exp in $experiments['Remediations']) {
            $policyName = $prefix + $exp['Name']
            if ($policyName -in $existingRem) {
                Write-Information -InformationAction Continue -MessageData "Exists, skipping: $policyName"
                continue
            }
            $detectionSplat = @{
                Body = $exp['Detection']
                Bom = [bool]$exp['Bom']
                PadKB = [int]$exp['PadKB']
            }
            $detection = ConvertTo-ScriptContent @detectionSplat
            $body = @{
                displayName            = $policyName
                description            = "$($exp['Question']) | detectionSha256=$($detection.Sha256)"
                publisher              = 'IntuneScriptLab'
                enforceSignatureCheck  = $false
                detectionScriptContent = $detection.Base64
            }
            # A detect-only remediation is one created without a remediation script. The assignment's
            # runRemediationScript only reflects whether one was uploaded: set to false on a policy that
            # has a remediation script, it changed nothing (REM-DETECTONLY, rounds 6 and 7)
            if (-not $exp['DetectOnly']) {
                $remediation = ConvertTo-ScriptContent -Body $exp['Remediation'] -Bom:([bool]$exp['Bom'])
                $body.remediationScriptContent = $remediation.Base64
            }
            if ($exp.ContainsKey('RunAs32Bit')) { $body.runAs32Bit = $exp['RunAs32Bit'] }
            if ($exp.ContainsKey('RunAsAccount')) { $body.runAsAccount = $exp['RunAsAccount'] }
            if (-not $PSCmdlet.ShouldProcess($policyName, 'Create remediation')) { continue }

            $schedule = ConvertTo-RemediationSchedule -Schedule $exp['Schedule']
            $policyUri = '/beta/deviceManagement/deviceHealthScripts'
            $policy = Invoke-MgGraphRequest -Method POST -Uri $policyUri -Body $body
            Invoke-MgGraphRequest -Method POST -Uri "$policyUri/$($policy['id'])/assign" -Body @{
                deviceHealthScriptAssignments = @(@{
                        target               = $target
                        runRemediationScript = -not [bool]$exp['DetectOnly']
                        runSchedule          = $schedule
                    })
            }
            Write-Information -InformationAction Continue -MessageData (
                "Created remediation $policyName (runAs32Bit=$($policy['runAs32Bit']), " +
                "runAsAccount=$($policy['runAsAccount']), " +
                "schedule=$($schedule['@odata.type'] -replace '.*\.', ''))")
        }

        $platformQuery = '/beta/deviceManagement/deviceManagementScripts?$select=id,displayName'
        $existingPs = @(Get-AllGraphItem -Uri $platformQuery | ForEach-Object { $_['displayName'] })
        foreach ($exp in $experiments['PlatformScripts']) {
            $policyName = $prefix + $exp['Name']
            if ($policyName -in $existingPs) {
                Write-Information -InformationAction Continue -MessageData "Exists, skipping: $policyName"
                continue
            }
            $contentSplat = @{
                Body = $exp['Script']
                Bom = [bool]$exp['Bom']
                PadKB = [int]$exp['PadKB']
            }
            $content = ConvertTo-ScriptContent @contentSplat
            $body = @{
                displayName           = $policyName
                description           = "$($exp['Question']) | sha256=$($content.Sha256)"
                fileName              = "$policyName.ps1"
                enforceSignatureCheck = $false
                scriptContent         = $content.Base64
            }
            if ($exp.ContainsKey('RunAs32Bit')) { $body.runAs32Bit = $exp['RunAs32Bit'] }
            if ($exp.ContainsKey('RunAsAccount')) { $body.runAsAccount = $exp['RunAsAccount'] }
            if (-not $PSCmdlet.ShouldProcess($policyName, 'Create platform script')) { continue }

            $policyUri = '/beta/deviceManagement/deviceManagementScripts'
            $policy = Invoke-MgGraphRequest -Method POST -Uri $policyUri -Body $body
            Invoke-MgGraphRequest -Method POST -Uri "$policyUri/$($policy['id'])/assign" -Body @{
                deviceManagementScriptAssignments = @(@{ target = $target })
            }
            Write-Information -InformationAction Continue -MessageData (
                "Created platform script $policyName (runAs32Bit=$($policy['runAs32Bit']), " +
                "runAsAccount=$($policy['runAsAccount']))")
        }

        if ($experiments['Win32Apps']) {
            Invoke-DeployWin32 -Experiments $experiments['Win32Apps'] -Target $target
        }
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}


function Invoke-DeployWin32 {
    <#
    .SYNOPSIS
        Packages, creates and assigns the Win32 app experiments, then relates them.

    .DESCRIPTION
        Fetches IntuneWinAppUtil.exe when it is missing and refuses it unless Microsoft signed it, builds
        one install.ps1 package for the script experiments and one package per MSI, and creates, uploads
        and assigns an ISL- app for each experiment whose name does not exist yet. A Graph error on one
        app is a warning and the next app is still deployed. Dependencies and supersedence are set once
        every app of the round exists.

    .PARAMETER Experiments
        The Win32Apps entries of Experiments.psd1.

    .PARAMETER Target
        The group assignment target that the apps are assigned to.

    .EXAMPLE
        Invoke-DeployWin32 -Experiments $experiments['Win32Apps'] -Target $target

        Deploys the round's Win32 apps to the validation group.

    .INPUTS
        None.

    .OUTPUTS
        System.Void. The function reports what it created on the information stream.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.Void])]
    param(
        [Parameter(Mandatory)]
        [array]$Experiments,

        [Parameter(Mandatory)]
        [hashtable]$Target
    )

    try {
        . (Join-Path -Path $PSScriptRoot -ChildPath 'Win32Content.ps1')
        if (-not (Test-Path -LiteralPath $IntuneWinAppUtilPath)) {
            # Microsoft's tool is not in the repo; fetch it and refuse anything not signed by Microsoft.
            # The tool and the package are built on this computer under -WhatIf as well, so that a
            # rehearsal gets as far as the first change to the tenant: the folders are pinned
            $toolFolder = Split-Path -Path $IntuneWinAppUtilPath -Parent
            $null = New-Item -ItemType Directory -Path $toolFolder -Force -WhatIf:$false -Confirm:$false
            $downloadMessage = "Downloading IntuneWinAppUtil.exe to $IntuneWinAppUtilPath"
            Write-Information -InformationAction Continue -MessageData $downloadMessage
            $toolUri = 'https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/' +
                'raw/master/IntuneWinAppUtil.exe'
            Invoke-WebRequest -Uri $toolUri -OutFile $IntuneWinAppUtilPath
        }
        $signature = Get-AuthenticodeSignature -LiteralPath $IntuneWinAppUtilPath
        $signer = $signature.SignerCertificate
        $signedByMicrosoft = $null -ne $signer -and $signer.Subject -match 'O=Microsoft Corporation'
        if ($signature.Status -ne 'Valid' -or -not $signedByMicrosoft) {
            $errorSplat = @{
                Message = ("IntuneWinAppUtil.exe at $IntuneWinAppUtilPath is not validly signed by Microsoft " +
                    "($($signature.Status)); refusing to run it")
                ErrorId = 'ToolSignatureInvalid'
                Category = 'SecurityError'
                TargetObject = $IntuneWinAppUtilPath
            }
            $PSCmdlet.ThrowTerminatingError((New-ValidationErrorRecord @errorSplat))
        }

        # One package for every app: install.ps1 = param block + probe + body
        $buildName = "ISL-Win32-$([guid]::NewGuid().ToString('N'))"
        $build = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath $buildName
        $sourceFolder = Join-Path -Path $build -ChildPath 'Source'
        $source = New-Item -ItemType Directory -Path $sourceFolder -Force -WhatIf:$false -Confirm:$false
        $probe = Get-Content -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath 'Probe.ps1') -Raw
        # .Replace, not -replace: the probe text contains `$_`, which a regex replacement would expand
        $installPath = Join-Path -Path $PSScriptRoot -ChildPath 'Win32Install.ps1'
        $install = (Get-Content -LiteralPath $installPath -Raw).Replace('# --PROBE--', $probe)
        # A mis-spliced script can still parse (param( becomes a command), so check the param block
        # survived
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($install, [ref]$null, [ref]$parseErrors)
        if ($parseErrors -or -not $ast.ParamBlock -or $ast.ParamBlock.Parameters.Count -ne 2) {
            $parseText = @($parseErrors | ForEach-Object { $_.Message }) -join '; '
            $errorSplat = @{
                Message = ("Composed install.ps1 is malformed: $parseText " +
                    "paramBlock=$($null -ne $ast.ParamBlock)")
                ErrorId = 'InstallScriptMalformed'
                Category = 'InvalidData'
            }
            $PSCmdlet.ThrowTerminatingError((New-ValidationErrorRecord @errorSplat))
        }
        [IO.File]::WriteAllText((Join-Path -Path $source -ChildPath 'install.ps1'), $install,
            [Text.UTF8Encoding]::new($true))
        $packageSplat = @{
            ToolPath = $IntuneWinAppUtilPath; SourceFolder = $source; SetupFile = 'install.ps1'
            OutputFolder = Join-Path -Path $build -ChildPath 'Package'
        }
        $package = New-IntuneWinPackage @packageSplat
        $scriptContent = Get-IntuneWinContent -PackagePath $package.FullName -WorkFolder $build
        Write-Information -InformationAction Continue -MessageData (
            "Packaged install.ps1: $($scriptContent.UnencryptedSize) bytes " +
                "($($scriptContent.EncryptedSize) encrypted)")
        $packages = @{}

        $win32Query = "/beta/deviceAppManagement/mobileApps?`$filter=isof('microsoft.graph.win32LobApp')" +
            "&`$select=id,displayName"
        $existingApps = @(Get-AllGraphItem -Uri $win32Query)
        $existing = @($existingApps | ForEach-Object { $_['displayName'] })
        $appIds = @{}
        foreach ($known in $existingApps) { $appIds[$known['displayName']] = $known['id'] }
        $relationships = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($exp in $Experiments) {
            $appDisplayName = $prefix + $exp['Name']
            if ($appDisplayName -in $existing) {
                Write-Information -InformationAction Continue -MessageData "Exists, skipping: $appDisplayName"
                continue
            }
            # An MSI experiment gets its own package built from the downloaded installer; Intune's
            # metadata (product code, version, upgrade code) comes out of the package XML
            $content = $scriptContent
            if ($exp['Package']) {
                $content = Get-MsiPackageContent -Package $exp['Package'] -Build $build -Cache $packages
            }
            # Script rules get the probe header through the encoder; file, registry and product code rules
            # are passed through as specified (GraphRules.ps1)
            if ($content.MsiInformation -and -not $exp['Detection'] -and -not $exp['DetectionRules']) {
                # The portal derives the MSI detection from the package; do the same
                $exp = @{} + $exp
                $productCode = $content.MsiInformation.productCode
                $exp.DetectionRules = @(@{ Type = 'ProductCode'; ProductCode = $productCode })
            }
            $rules = Get-Win32AppRuleSet -Experiment $exp -Encode {
                param($Body, $Bom) (ConvertTo-ScriptContent -Body $Body -Bom:([bool]$Bom)).Base64
            }
            $sha = ''
            if ($exp['Detection']) {
                $detection = ConvertTo-ScriptContent -Body $exp['Detection'] -Bom:([bool]$exp['Bom'])
                $sha = " | detectionSha256=$($detection.Sha256)"
            }
            $intent = if ($exp['Intent']) { $exp['Intent'] } else { 'required' }
            $runAs = if ($exp['InstallContext']) { $exp['InstallContext'] } else { 'system' }
            $installScript = "powershell.exe -ExecutionPolicy Bypass -File install.ps1 -Experiment $($exp['Name'])"
            if ($exp['InstallCommand']) {
                $installCommand = $exp['InstallCommand']
            } elseif ($content.MsiInformation) {
                $installCommand = "msiexec /i `"$($content.SetupFile)`" /qn"
            } else {
                $installCommand = $installScript
            }
            if ($exp['UninstallCommand']) {
                $uninstallCommand = $exp['UninstallCommand']
            } elseif ($content.MsiInformation) {
                $uninstallCommand = "msiexec /x `"$($content.MsiInformation.productCode)`" /qn"
            } else {
                $uninstallCommand = "$installScript -Uninstall"
            }
            $body = @{
                '@odata.type'                  = '#microsoft.graph.win32LobApp'
                displayName                    = $appDisplayName
                description                    = "$($exp['Question'])$sha"
                publisher                      = 'IntuneScriptLab'
                fileName                       = $content.FileName
                setupFilePath                  = $content.SetupFile
                installCommandLine             = $installCommand
                uninstallCommandLine           = $uninstallCommand
                installExperience              = @{ runAsAccount = $runAs; deviceRestartBehavior = 'suppress' }
                allowedArchitectures           = 'x64,x86'
                minimumSupportedWindowsRelease = '1607'
                rules                          = @($rules)
                returnCodes                    = @(
                    @{ returnCode = 0; type = 'success' }, @{ returnCode = 3010; type = 'softReboot' },
                    @{ returnCode = 1641; type = 'hardReboot' }, @{ returnCode = 1618; type = 'retry' }
                )
            }
            if ($content.MsiInformation) { $body.msiInformation = $content.MsiInformation }
            # Base requirements (OS release, architecture, disk, memory, CPU) as the portal's Requirements
            # page sets them: keys are the Graph property names
            $requirements = $exp['Requirements']
            if ($requirements) {
                foreach ($key in @($requirements.Keys)) { $body[$key] = $requirements[$key] }
            }
            # An assignment filter, created on first use and named after the experiment
            $assignTarget = @{} + $Target
            $filterSpec = $exp['Filter']
            if ($filterSpec) {
                $filterName = "$prefix$($exp['Name'])"
                $filterId = Get-AssignmentFilterId -DisplayName $filterName -Rule $filterSpec['Rule']
                $assignTarget.deviceAndAppManagementAssignmentFilterId = $filterId
                $filterMode = if ($filterSpec['Mode']) { $filterSpec['Mode'] } else { 'include' }
                $assignTarget.deviceAndAppManagementAssignmentFilterType = $filterMode
            }
            $ruleCount = @($rules).Count
            if (-not $PSCmdlet.ShouldProcess($appDisplayName, "Create Win32 app ($intent, $ruleCount rules)")) {
                continue
            }

            # One rejected rule must not end the round: Graph's answer is the finding, the rest still
            # deploys
            try {
                $app = Invoke-MgGraphRequest -Method POST -Uri '/beta/deviceAppManagement/mobileApps' -Body $body
                $appIds[$appDisplayName] = $app['id']
                Publish-Win32AppContent -AppId $app['id'] -Content $content
                # A dependency child is created but not assigned: Intune is supposed to install it for the
                # parent
                if (-not ($exp.ContainsKey('Assign') -and -not $exp['Assign'])) {
                    $assignUri = "/beta/deviceAppManagement/mobileApps/$($app['id'])/assign"
                    Invoke-MgGraphRequest -Method POST -Uri $assignUri -Body @{
                        mobileAppAssignments = @(@{
                                '@odata.type' = '#microsoft.graph.mobileAppAssignment'
                                intent        = $intent
                                target        = $assignTarget
                                settings      = @{
                                    '@odata.type'                = '#microsoft.graph.win32LobAppAssignmentSettings'
                                    notifications                = 'hideAll'
                                    deliveryOptimizationPriority = 'notConfigured'
                                }
                            })
                    }
                }
                $dependsOn = $exp['DependsOn']
                if ($dependsOn) {
                    $dependencyType = if ($dependsOn['Type']) { $dependsOn['Type'] } else { 'autoInstall' }
                    $relationships.Add(@{ App = $appDisplayName; Target = "$prefix$($dependsOn['App'])"
                            Relationship = @{
                                '@odata.type' = '#microsoft.graph.mobileAppDependency'
                                dependencyType = $dependencyType
                            }
                        })
                }
                $supersedes = $exp['Supersedes']
                if ($supersedes) {
                    $supersedenceType = if ($supersedes['Type']) { $supersedes['Type'] } else { 'update' }
                    $relationships.Add(@{ App = $appDisplayName; Target = "$prefix$($supersedes['App'])"
                            Relationship = @{
                                '@odata.type'    = '#microsoft.graph.mobileAppSupersedence'
                                supersedenceType = $supersedenceType
                            }
                        })
                }
                $createdMessage = "Created Win32 app $appDisplayName ($intent, $runAs, $(@($rules).Count) rules)"
                Write-Information -InformationAction Continue -MessageData $createdMessage
            } catch {
                Write-Warning ("Skipping $appDisplayName after a Graph error (an app created without content " +
                    "or assignment is left behind; Remove clears it): $($_.Exception.Message)")
            }
        }

        # Relationships need both apps to exist, so they are set once every app of the round is created
        foreach ($item in $relationships) {
            if (-not $appIds[$item['App']] -or -not $appIds[$item['Target']]) {
                Write-Warning "Relationship $($item['App']) -> $($item['Target']) skipped: an app is missing"
                continue
            }
            $relationship = @{ targetId = $appIds[$item['Target']] } + $item['Relationship']
            try {
                $uri = "/beta/deviceAppManagement/mobileApps/$($appIds[$item['App']])/updateRelationships"
                Invoke-MgGraphRequest -Method POST -Uri $uri -Body @{ relationships = @($relationship) }
                Write-Information -InformationAction Continue -MessageData ("Related $($item['App']) -> " +
                    "$($item['Target']) ($($relationship['@odata.type'] -replace '.*\.', ''))")
            } catch {
                Write-Warning ("Relationship $($item['App']) -> $($item['Target']) failed: " +
                    "$($_.Exception.Message)")
            }
        }
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}


function Get-AssignmentFilterId {
    <#
    .SYNOPSIS
        Gets the id of a Windows device assignment filter, creating it when needed.

    .DESCRIPTION
        A device assignment filter for Windows, reused by name across deploys. A filter with the display
        name is reused as it is; otherwise one is created with the rule.

    .PARAMETER DisplayName
        The filter's display name.

    .PARAMETER Rule
        The filter rule, used only when the filter is created.

    .EXAMPLE
        Get-AssignmentFilterId -DisplayName 'ISL-W32-FILTER' -Rule '(device.osVersion -startsWith "10.0")'

        Gets the id of the experiment's filter.

    .INPUTS
        None.

    .OUTPUTS
        System.String. The filter's id.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$DisplayName,

        [Parameter(Mandatory)]
        [string]$Rule
    )

    try {
        $existing = Get-AllGraphItem -Uri '/beta/deviceManagement/assignmentFilters?$select=id,displayName' |
            Where-Object { $_['displayName'] -eq $DisplayName } | Select-Object -First 1
        if ($existing) {
            $filterId = $existing['id']
        } else {
            $filter = Invoke-MgGraphRequest -Method POST -Uri '/beta/deviceManagement/assignmentFilters' -Body @{
                displayName                    = $DisplayName
                description                    = 'IntuneScriptLab validation filter. Safe to delete.'
                platform                       = 'windows10AndLater'
                rule                           = $Rule
                assignmentFilterManagementType = 'devices'
                roleScopeTags                  = @('0')
            }
            $createdMessage = "Created assignment filter $DisplayName ($Rule)"
            Write-Information -InformationAction Continue -MessageData $createdMessage
            $filterId = $filter['id']
        }
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
    $filterId
}


function Get-MsiPackageContent {
    <#
    .SYNOPSIS
        Packages an MSI experiment's installer and returns its upload content.

    .DESCRIPTION
        Downloads an installer once into Tools\, packages it with IntuneWinAppUtil and returns the content
        object (with msiInformation from the package XML); the same package is reused across experiments.
        When the package names a Sha256, an installer with another hash ends the function with an error.

    .PARAMETER Package
        The experiment's Package entry: FileName, Url and optionally Sha256.

    .PARAMETER Build
        The scratch folder that the package is built in.

    .PARAMETER Cache
        The packages built so far in this round, by file name; the new one is added to it.

    .EXAMPLE
        Get-MsiPackageContent -Package $exp['Package'] -Build $build -Cache $packages

        Gets the content object for the experiment's installer.

    .INPUTS
        None.

    .OUTPUTS
        System.Management.Automation.PSObject. The content object that Get-IntuneWinContent returns.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Package,

        [Parameter(Mandatory)]
        [string]$Build,

        [Parameter(Mandatory)]
        [hashtable]$Cache
    )

    $fileName = $Package['FileName']
    if ($Cache.ContainsKey($fileName)) { return $Cache[$fileName] }
    try {
        $tools = Split-Path -Path $IntuneWinAppUtilPath -Parent
        $installer = Join-Path -Path $tools -ChildPath $fileName
        if (-not (Test-Path -LiteralPath $installer)) {
            Write-Information -InformationAction Continue -MessageData "Downloading $($Package['Url'])"
            Invoke-WebRequest -Uri $Package['Url'] -OutFile $installer
        }
        if ($Package['Sha256']) {
            $actual = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash
            if ($actual -ne $Package['Sha256']) {
                $errorSplat = @{
                    Message = "$fileName hash $actual does not match $($Package['Sha256'])"
                    ErrorId = 'InstallerHashMismatch'
                    Category = 'InvalidData'
                    TargetObject = $installer
                }
                $PSCmdlet.ThrowTerminatingError((New-ValidationErrorRecord @errorSplat))
            }
        }
        $sourceFolder = Join-Path -Path $Build -ChildPath $fileName
        $source = New-Item -ItemType Directory -Path $sourceFolder -Force -WhatIf:$false -Confirm:$false
        Copy-Item -LiteralPath $installer -Destination $source -WhatIf:$false -Confirm:$false
        $packageSplat = @{
            ToolPath     = $IntuneWinAppUtilPath
            SourceFolder = $source
            SetupFile    = $fileName
            OutputFolder = Join-Path -Path $Build -ChildPath "Package-$fileName"
        }
        $built = New-IntuneWinPackage @packageSplat
        $content = Get-IntuneWinContent -PackagePath $built.FullName -WorkFolder $source
        $msiInformation = $content.MsiInformation
        $productCode = if ($msiInformation) { $msiInformation['productCode'] } else { $null }
        $productVersion = if ($msiInformation) { $msiInformation['productVersion'] } else { $null }
        Write-Information -InformationAction Continue -MessageData ("Packaged ${fileName}: " +
            "$($content.UnencryptedSize) bytes, product $productCode $productVersion")
        $Cache[$fileName] = $content
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
    $content
}


function Invoke-Prepare {
    <#
    .SYNOPSIS
        Prepares the VM's lab folder and runs Fixtures.ps1 on it.

    .DESCRIPTION
        Creates C:\ProgramData\IntuneScriptLab on the VM with Modify for BUILTIN\Users, so user-context
        probes can write their own files, then runs Fixtures.ps1 there. Both steps ask ShouldProcess once.

    .EXAMPLE
        Invoke-Prepare

        Prepares the VM that the script's VmId names.

    .INPUTS
        None.

    .OUTPUTS
        System.String. What the VM printed for each step.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param()

    if ($PSCmdlet.ShouldProcess("VM $VmId", 'Create C:\ProgramData\IntuneScriptLab with user write access')) {
        try {
            $prepared = Invoke-GuestPowerShell -Script @'
$lab = 'C:\ProgramData\IntuneScriptLab'
New-Item -ItemType Directory -Path $lab -Force | Out-Null
# BUILTIN\Users: Modify, inherited, so user-context probes can write their own files
$acl = Get-Acl -Path $lab
$rule = [Security.AccessControl.FileSystemAccessRule]::new(
    [Security.Principal.SecurityIdentifier]::new('S-1-5-32-545'), 'Modify',
    'ContainerInherit,ObjectInherit', 'None', 'Allow')
$acl.AddAccessRule($rule)
Set-Acl -Path $lab -AclObject $acl
"prepared $lab on $env:COMPUTERNAME"
'@
            # Files, registry keys and the MSI survey the rule experiments look at
            $fixturesPath = Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures.ps1'
            $fixtures = Get-Content -LiteralPath $fixturesPath -Raw
            $fixtureSplat = @{ Script = $fixtures; RemoteName = 'fixtures.ps1'; TimeoutSeconds = 300 }
            $fixtureOutput = Invoke-GuestScriptFile @fixtureSplat
        } catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
        $prepared
        $fixtureOutput
    }
}


function Invoke-Trigger {
    <#
    .SYNOPSIS
        Restarts the Intune Management Extension on the VM so it fetches policy now.

    .DESCRIPTION
        Restart-Service reports Running and restarts nothing: the stop fails and the process keeps
        its start time (round 11, VM 126). Stopping the service's process and then starting the
        service fetched new assignments within ten minutes. Both start times are printed, so a
        restart that did not happen shows as an unchanged Before/After. The restart asks ShouldProcess.

    .EXAMPLE
        Invoke-Trigger

        Restarts the agent on the VM that the script's VmId names.

    .INPUTS
        None.

    .OUTPUTS
        System.String. The service status and the process start times before and after.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param()

    if ($PSCmdlet.ShouldProcess("VM $VmId", 'Restart IntuneManagementExtension')) {
        try {
            $restarted = Invoke-GuestPowerShell -Script @'
$name = 'IntuneManagementExtension'
$service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$name'"
$before = if ($service.ProcessId) { (Get-Process -Id $service.ProcessId).StartTime.ToString('o') }
Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
if ($service.ProcessId -and (Get-Process -Id $service.ProcessId -ErrorAction SilentlyContinue)) {
    Stop-Process -Id $service.ProcessId -Force
}
Start-Service -Name $name
$service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$name'"
$after = if ($service.ProcessId) { (Get-Process -Id $service.ProcessId).StartTime.ToString('o') }
"Status=$((Get-Service -Name $name).Status) Before=$before After=$after"
'@
        } catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
        $restarted
    }
}


function Invoke-Collect {
    <#
    .SYNOPSIS
        Writes Intune's run states and the device's probe records to a results file.

    .DESCRIPTION
        Reads every ISL- remediation, platform script and Win32 app with its run states, assignments and
        install status from Graph, runs a collect script on the VM that packs the probe records, registry
        reports and agent log lines, and writes both to Results\round-<timestamp>.json. -AppName limits
        the Win32 apps and -Since the probe records. The device's payload is checked against the length
        and hash that the device reported.

    .EXAMPLE
        Invoke-Collect

        Collects the round and returns the path of the results file.

    .INPUTS
        None.

    .OUTPUTS
        System.String. The path of the results file.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    try {
        $remediations = foreach ($policy in (Get-AllGraphItem -Uri '/beta/deviceManagement/deviceHealthScripts')) {
            if (-not $policy['displayName'].StartsWith($prefix)) { continue }
            [ordered]@{
                Name         = $policy['displayName']
                Id           = $policy['id']
                Description  = $policy['description']
                RunAs32Bit   = $policy['runAs32Bit']
                RunAsAccount = $policy['runAsAccount']
                RunStates    = Get-AllGraphItem -Uri ("/beta/deviceManagement/deviceHealthScripts/" +
                    "$($policy['id'])/deviceRunStates")
            }
        }
        $platformUri = '/beta/deviceManagement/deviceManagementScripts'
        $platform = foreach ($policy in (Get-AllGraphItem -Uri $platformUri)) {
            if (-not $policy['displayName'].StartsWith($prefix)) { continue }
            [ordered]@{
                Name         = $policy['displayName']
                Id           = $policy['id']
                Description  = $policy['description']
                RunAs32Bit   = $policy['runAs32Bit']
                RunAsAccount = $policy['runAsAccount']
                RunStates    = Get-AllGraphItem -Uri "$platformUri/$($policy['id'])/deviceRunStates"
            }
        }
        $apps = @(Get-AllGraphItem -Uri ("/beta/deviceAppManagement/mobileApps?" +
                "`$filter=isof('microsoft.graph.win32LobApp')") |
            Where-Object { $_['displayName'].StartsWith($prefix) })
        if ($AppName) {
            $apps = @($apps | Where-Object {
                    $candidate = $_['displayName'].Substring($prefix.Length)
                    @($AppName | Where-Object { $candidate -like $_ }).Count -gt 0
                })
        }
        $win32 = foreach ($app in $apps) {
            $assignmentsUri = "/beta/deviceAppManagement/mobileApps/$($app['id'])/assignments"
            $assignments = @(Get-AllGraphItem -Uri $assignmentsUri)
            # As member enumeration gives it: one intent for each assignment that has one, and one null
            # for an app without any (a dependency child)
            $intentValues = @($assignments | ForEach-Object { if ($_.Contains('intent')) { $_['intent'] } })
            if ($intentValues.Count -eq 0) { $intentValues = @($null) }
            [ordered]@{
                Name          = $app['displayName']
                Id            = $app['id']
                Description   = $app['description']
                Rules         = @($app['rules'] |
                    ForEach-Object {
                        $rule = [ordered]@{}
                        foreach ($k in ($_.Keys | Sort-Object)) {
                            if ($k -ne 'scriptContent') { $rule[$k] = $_[$k] }
                        }
                        $rule
                    })
                Intent        = @($intentValues)
                InstallStatus = @(Get-Win32InstallStatusReport -AppId $app['id'] |
                        Select-Object -Property DeviceName, UserPrincipalName, AppInstallState_loc,
                        AppInstallStateDetails_loc, HexErrorCode, LastModifiedDateTime)
            }
        }

        $deviceScript = @'
$ErrorActionPreference = 'SilentlyContinue'
$appWorkloadLog = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\AppWorkload.log'
function Get-RegTree($Path) {
    Get-ChildItem -Path $Path -Recurse | ForEach-Object {
        $props = Get-ItemProperty -Path $_.PSPath
        $values = [ordered]@{}
        foreach ($n in $_.GetValueNames()) { $values[$n] = $props.$n }
        if ($values.Count) { [ordered]@{ Key = $_.Name; Values = $values } }
    }
}
$ime = 'HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension'
[ordered]@{
    # Every probe record, or only those from -Since on: Time is written with ToString('o') in UTC,
    # so the strings compare in time order
    Probes          = Get-ChildItem 'C:\ProgramData\IntuneScriptLab\*.jsonl' | ForEach-Object {
        Get-Content -Path $_.FullName -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json } |
            Where-Object { -not '--SINCE--' -or "$($_.Time)" -ge '--SINCE--' }
    }
    Markers         = @(Get-ChildItem 'C:\ProgramData\IntuneScriptLab' -File |
        Where-Object { $_.Extension -in '.marker', '.uninstalled', '.installed' } | ForEach-Object Name)
    HealthReports   = @(Get-RegTree "$ime\SideCarPolicies\Scripts")
    PlatformReports = @(Get-RegTree "$ime\Policies")
    Win32Reports    = @(Get-RegTree "$ime\Win32Apps")
    # AppWorkload.log lines about detection/requirement/rules/install, most recent 2,000
    AppWorkloadLog  = @(Get-Content -Path $appWorkloadLog -Tail 20000 |
        Where-Object { $_ -match ('etect|equirement|xit code|ExitCode|nstall|ISL-|stdout|stderr|output|' +
            '[Rr]ule|pplicab|ignature|ependen|upersed|[Ff]ilter') } |
        ForEach-Object { $_ -replace '<!\[LOG\[', '' -replace '\]LOG\]!>.*time="([^".]+)[^"]*".*', ' @$1' } |
        Select-Object -Last 2000)
    # Agent log: platform-script retries (download count, policy result) for the ISL policies
    ImeLog          = @(Get-ChildItem ('C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\' +
            'IntuneManagementExtension*.log') |
        Sort-Object LastWriteTime | ForEach-Object { Get-Content $_.FullName -Tail 30000 } |
        Where-Object {
            $_ -match '--POLICYIDS--' -and $_ -match 'download count|policy result|Processing policy|skip'
        } |
        ForEach-Object {
            $_ -replace '<!\[LOG\[', '' -replace '\]LOG\]!>.*time="([^".]+)[^"]*" date="([^"]+)".*', ' @$2 $1'
        } |
        Select-Object -Last 600)
    # HealthScripts.log: scheduling decisions for the ISL remediations
    HealthScriptLog = @(Get-ChildItem ('C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\' +
            'HealthScripts*.log') |
        Sort-Object LastWriteTime | ForEach-Object { Get-Content $_.FullName -Tail 30000 } |
        Where-Object { $_ -match '--POLICYIDS--' -and $_ -match 'queue|chedul|[Rr]un[Oo]nce|next|interval' } |
        ForEach-Object {
            $_ -replace '<!\[LOG\[', '' -replace '\]LOG\]!>.*time="([^".]+)[^"]*" date="([^"]+)".*', ' @$2 $1'
        } |
        Select-Object -Last 600)
} | ConvertTo-Json -Depth 8 -Compress | ForEach-Object {
    # Gzip, then base64 so non-ASCII survives the guest agent's console code page: the JSON of a
    # device with a month of hourly probe records is 13 MB and packs to under 400 KB, which the
    # host reads in one guest agent call
    $json = [Text.Encoding]::UTF8.GetBytes($_)
    $packed = New-Object System.IO.MemoryStream
    $mode = [System.IO.Compression.CompressionMode]::Compress
    $gzip = New-Object System.IO.Compression.GZipStream $packed, $mode
    $gzip.Write($json, 0, $json.Length)
    $gzip.Dispose()
    $b64 = [Convert]::ToBase64String($packed.ToArray())
    [IO.File]::WriteAllText('C:\ProgramData\IntuneScriptLab\collect.b64', $b64)
    # The length and a hash of the text, so the host can tell whether it arrived as written
    $sha = [Security.Cryptography.SHA256]::Create()
    $hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::ASCII.GetBytes($b64))) -replace '-', ''
    "$($b64.Length) $hash"
}
'@
        # The log filters need the policy ids and the probe filter its time; the device script is a
        # literal, so they are spliced in
        $policyIds = foreach ($entry in (@($remediations) + @($platform))) {
            if ($null -ne $entry -and $entry['Id']) { $entry['Id'] }
        }
        # A nested function's $PSBoundParameters is its own; an unbound [datetime] is MinValue
        $sinceText = if ($Since -gt [datetime]::MinValue) { $Since.ToUniversalTime().ToString('o') } else { '' }
        $deviceScript = $deviceScript.Replace('--POLICYIDS--', ($policyIds -join '|'))
        $deviceScript = $deviceScript.Replace('--SINCE--', $sinceText)
        $summary = Invoke-GuestScriptFile -Script $deviceScript -TimeoutSeconds 1500 -Detach
        if ("$summary" -notmatch '^\s*(\d+) ([0-9A-Fa-f]{64})\s*$') {
            $errorSplat = @{
                Message = ("The device collect script returned no payload size and hash ('$summary'); " +
                    'see the warning above')
                ErrorId = 'CollectPayloadMissing'
                Category = 'InvalidResult'
            }
            $PSCmdlet.ThrowTerminatingError((New-ValidationErrorRecord @errorSplat))
        }
        $encoded = Receive-GuestFile -RemotePath 'C:\ProgramData\IntuneScriptLab\collect.b64' -Sha256 $Matches[2]
        $device = Expand-GzipText -Base64 $encoded | ConvertFrom-Json

        $null = New-Item -ItemType Directory -Path $ResultsPath -Force
        $file = Join-Path -Path $ResultsPath -ChildPath ("round-{0:yyyyMMdd-HHmmss}.json" -f (Get-Date))
        [ordered]@{
            CollectedUtc    = (Get-Date).ToUniversalTime().ToString('o')
            Remediations    = @($remediations)
            PlatformScripts = @($platform)
            Win32Apps       = @($win32)
            Device          = $device
        } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $file -Encoding utf8
        Write-Information -InformationAction Continue -MessageData "Results written to $file"
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
    $file
}


function Invoke-Remove {
    <#
    .SYNOPSIS
        Deletes every ISL- app, policy and filter and the validation group.

    .DESCRIPTION
        Deletes the Win32 apps, remediations, platform scripts and assignment filters whose display name
        starts with ISL-, then the validation group. Each deletion asks ShouldProcess.

    .EXAMPLE
        Invoke-Remove -WhatIf

        Lists what the clean-up would delete.

    .INPUTS
        None.

    .OUTPUTS
        System.Void. The function writes nothing to the pipeline.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.Void])]
    param()

    try {
        $win32Query = "/beta/deviceAppManagement/mobileApps?`$filter=isof('microsoft.graph.win32LobApp')" +
            "&`$select=id,displayName"
        foreach ($app in (Get-AllGraphItem -Uri $win32Query)) {
            $appDisplayName = $app['displayName']
            if ($appDisplayName.StartsWith($prefix) -and
                $PSCmdlet.ShouldProcess($appDisplayName, 'Delete Win32 app')) {
                Invoke-MgGraphRequest -Method DELETE -Uri "/beta/deviceAppManagement/mobileApps/$($app['id'])"
            }
        }
        foreach ($kind in 'deviceHealthScripts', 'deviceManagementScripts') {
            foreach ($policy in (Get-AllGraphItem -Uri "/beta/deviceManagement/$kind`?`$select=id,displayName")) {
                $policyName = $policy['displayName']
                if ($policyName.StartsWith($prefix) -and $PSCmdlet.ShouldProcess($policyName, 'Delete')) {
                    Invoke-MgGraphRequest -Method DELETE -Uri "/beta/deviceManagement/$kind/$($policy['id'])"
                }
            }
        }
        $filterQuery = '/beta/deviceManagement/assignmentFilters?$select=id,displayName'
        foreach ($filter in (Get-AllGraphItem -Uri $filterQuery)) {
            $filterName = $filter['displayName']
            if ($filterName.StartsWith($prefix) -and $PSCmdlet.ShouldProcess($filterName, 'Delete filter')) {
                $filterUri = "/beta/deviceManagement/assignmentFilters/$($filter['id'])"
                Invoke-MgGraphRequest -Method DELETE -Uri $filterUri
            }
        }
        $groupQuery = "/v1.0/groups?`$filter=displayName eq '$GroupName'"
        $group = (Invoke-MgGraphRequest -Method GET -Uri $groupQuery)['value'] | Select-Object -First 1
        if ($group -and $PSCmdlet.ShouldProcess($GroupName, 'Delete group')) {
            Invoke-MgGraphRequest -Method DELETE -Uri "/v1.0/groups/$($group['id'])"
        }
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}


Connect-LabGraph
switch ($Action) {
    'Prepare' { Invoke-Prepare }
    'Deploy' { Invoke-Deploy }
    'Trigger' { Invoke-Trigger }
    'Collect' { Invoke-Collect }
    'Remove' { Invoke-Remove }
}
