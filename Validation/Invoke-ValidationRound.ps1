#Requires -Version 7.6
#Requires -Modules Microsoft.Graph.Authentication

<#
.SYNOPSIS
    Deploys IntuneScriptLab validation experiments to a test device, triggers them, and collects
    what both Intune and the device recorded.

.DESCRIPTION
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

.EXAMPLE
    $conn = @{ TenantId = '<tenant>'; ClientId = '<app>'; CertificateThumbprint = '<thumb>' }
    .\Invoke-ValidationRound.ps1 -Action Deploy @conn -AzureADDeviceId '<entra device id>'
    .\Invoke-ValidationRound.ps1 -Action Trigger -ProxmoxHost pve -VmId 124
    .\Invoke-ValidationRound.ps1 -Action Collect @conn -ProxmoxHost pve -VmId 124
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

    # Entra deviceId (not object id) of the test device; required for Deploy.
    [string]$AzureADDeviceId,

    # Deploy only the experiments whose Name matches (wildcards), for a round that needs an earlier
    # phase to have run first (supersedence: the superseded app must be installed before the new one)
    [string[]]$Name,

    # Collect: only the Win32 apps whose experiment name matches (wildcards), since each app costs an
    # install-status export job of 20-30 seconds
    [string[]]$AppName,

    # Collect: only the probe records written at or after this time (the records of a device that
    # has run the hourly experiments for weeks are most of the payload); every record when omitted
    [datetime]$Since,

    [string]$GroupName = 'ISL-Validation-Devices',

    # Deploy: leave the group's membership alone (a user group for user-targeted experiments)
    [switch]$SkipDeviceMember,

    [string]$ProxmoxHost = 'pve',
    [int]$VmId = 124,
    [string]$ExperimentsPath = (Join-Path -Path $PSScriptRoot -ChildPath 'Experiments.psd1'),
    [string]$ResultsPath = (Join-Path -Path $PSScriptRoot -ChildPath 'Results'),

    # Microsoft's Win32 Content Prep Tool; needed only when Experiments.psd1 has Win32Apps.
    [string]$IntuneWinAppUtilPath = (Join-Path -Path $PSScriptRoot -ChildPath 'Tools\IntuneWinAppUtil.exe')
)

$ErrorActionPreference = 'Stop'
$prefix = 'ISL-'
. (Join-Path -Path $PSScriptRoot -ChildPath 'GraphRules.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'GuestAgent.ps1')

function Connect-LabGraph {
    if ($Action -notin 'Trigger', 'Prepare' -and -not (Get-MgContext)) {
        if (-not ($TenantId -and $ClientId -and $CertificateThumbprint)) {
            throw 'TenantId, ClientId and CertificateThumbprint are required for this action.'
        }
        $connectSplat = @{
            TenantId = $TenantId; ClientId = $ClientId; CertificateThumbprint = $CertificateThumbprint
        }
        Connect-MgGraph @connectSplat -NoWelcome
    }
}

function Get-AllGraphItem {
    param([Parameter(Mandatory)][string]$Uri)
    $items = [System.Collections.Generic.List[object]]::new()
    while ($Uri) {
        $page = Invoke-MgGraphRequest -Method GET -Uri $Uri
        if ($page.value) { $items.AddRange([object[]]$page.value) }
        $Uri = $page.'@odata.nextLink'
    }
    $items
}

function Get-Win32InstallStatusReport {
    # Per-device install state for one app, via the reports export job (the admin center's own path;
    # mobileApps/{id}/deviceStatuses and getDeviceInstallStatusReport are both gone from beta). The
    # report refuses to run without an ApplicationId filter, so it is one job per app, and the jobs
    # have to be run one at a time: ten submitted together took the full deadline and two never
    # finished, so the service queues them. Collect -AppName keeps a round to its own apps.
    param([Parameter(Mandatory)][string]$AppId)
    $exportJobs = '/beta/deviceManagement/reports/exportJobs'
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
            $job = Invoke-MgGraphRequest -Method GET -Uri "$exportJobs/$($job.id)"
        }
        catch {
            Write-Warning "Export job poll failed, retrying: $($_.Exception.Message)"
            Start-Sleep -Seconds 10
        }
    } while ($job.status -ne 'completed' -and (Get-Date) -lt $deadline)
    if ($job.status -ne 'completed') {
        Write-Warning "Install status export job for app $AppId still $($job.status); skipping"
        return
    }
    Read-ExportJobCsv -Url $job.url -JobId $job.id
}
function Read-ExportJobCsv {
    # Downloads a finished export job (a zip holding one CSV) and returns its rows
    param([Parameter(Mandatory)][string]$Url, [Parameter(Mandatory)][string]$JobId)
    $zipPath = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath "$JobId.zip"
    Invoke-WebRequest -Uri $Url -OutFile $zipPath
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        foreach ($entry in $zip.Entries) {
            $reader = [IO.StreamReader]::new($entry.Open())
            $reader.ReadToEnd() | ConvertFrom-Csv
            $reader.Dispose()
        }
    }
    finally { $zip.Dispose(); Remove-Item -Path $zipPath -ErrorAction SilentlyContinue }
}
function ConvertTo-ScriptContent {
    # Probe header + experiment body, as base64 of UTF-8 bytes with or without a BOM. PadKB appends
    # that many kilobytes of comment lines, for the size-limit experiments.
    param([Parameter(Mandatory)][string]$Body, [bool]$Bom, [int]$PadKB)
    $probePath = Join-Path -Path $PSScriptRoot -ChildPath 'Probe.ps1'
    $text = (Get-Content -Path $probePath -Raw) + "`r`n" + $Body + "`r`n"
    if ($PadKB -gt 0) {
        $line = '# ' + ('pad' * 33) + "`r`n"
        $text += $line * [int][Math]::Ceiling($PadKB * 1024 / $line.Length)
    }
    $bytes = [Text.UTF8Encoding]::new($Bom).GetPreamble() + [Text.Encoding]::UTF8.GetBytes($text)
    [pscustomobject]@{
        Base64 = [Convert]::ToBase64String($bytes)
        Sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([byte[]]$bytes))
    }
}

function Expand-GzipText {
    # The collect payload as the device wrote it: base64 of gzip of UTF-8 JSON, back to the JSON text
    param([Parameter(Mandatory)][string]$Base64)
    $packed = [System.IO.MemoryStream]::new([Convert]::FromBase64String($Base64))
    $gzip = [System.IO.Compression.GZipStream]::new($packed, [System.IO.Compression.CompressionMode]::Decompress)
    $plain = [System.IO.MemoryStream]::new()
    try { $gzip.CopyTo($plain) }
    finally { $gzip.Dispose(); $packed.Dispose() }
    [Text.Encoding]::UTF8.GetString($plain.ToArray())
}

function Invoke-GuestScriptFile {
    # Runs a script that is too long for the guest agent's command line (a few KB): the script is
    # written to the VM through Send-GuestFile and run by path. The guest agent calls themselves
    # are in GuestAgent.ps1.
    param(
        [Parameter(Mandatory)][string]$Script,
        [int]$TimeoutSeconds = 900,
        [string]$RemoteName = 'collect.ps1',
        # Start the script detached and poll for its done marker instead of waiting on one call
        [switch]$Detach
    )
    $remote = "C:\ProgramData\IntuneScriptLab\$RemoteName"
    $bytes = [Text.UTF8Encoding]::new($true).GetPreamble() + [Text.Encoding]::UTF8.GetBytes($Script)
    Send-GuestFile -RemotePath $remote -Bytes $bytes
    if (-not $Detach) {
        # The agent's own powershell.exe runs under the machine execution policy, which refuses a
        # script file on a fresh device; the process-scoped bypass is what -File -ExecutionPolicy
        # Bypass would have given
        return Invoke-GuestPowerShell -TimeoutSeconds $TimeoutSeconds -Script (
            "Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force; & '$remote'")
    }
    # A script that runs for minutes is started detached and watched through a done marker with short
    # calls, so no single guest agent call has to stay open for it; its output is read from a file
    foreach ($suffix in '.out', '.err', '.done', '.started') {
        $null = Invoke-GuestPowerShell -Script "Remove-Item -Path '$remote$suffix' -ErrorAction SilentlyContinue"
    }
    # A runner batch file carries the redirections, so the launch itself has no nested quoting; it is
    # delivered as base64 for the same reason
    $runner = @(
        '@echo off'
        "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$remote`" 1>`"$remote.out`" 2>`"$remote.err`""
        "echo done>`"$remote.done`""
    ) -join "`r`n"
    $runnerB64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($runner))
    # A guest call can run twice (GuestAgent.ps1), and a second runner would find the output file held
    # by the first, skip the script and write the done marker at once: the started marker makes a
    # repeated launch a no-op
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
    if ($done -ne 'True') { throw "Detached guest script $RemoteName did not finish within $TimeoutSeconds s" }
    $errText = Invoke-GuestPowerShell -Script "Get-Content -Path '$remote.err' -Raw -ErrorAction SilentlyContinue"
    if ($errText -and $errText -notmatch '^\s*$' -and $errText -notmatch 'Preparing modules') {
        $errHead = $errText.Substring(0, [Math]::Min(400, $errText.Length))
        Write-Warning "Detached guest script ${RemoteName}: $errHead"
    }
    Invoke-GuestPowerShell -Script "Get-Content -Path '$remote.out' -Raw -ErrorAction SilentlyContinue"
}

function Invoke-Deploy {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if (-not $AzureADDeviceId -and -not $SkipDeviceMember) { throw 'AzureADDeviceId is required for Deploy.' }
    $experiments = Import-PowerShellDataFile -Path $ExperimentsPath
    if ($Name) {
        foreach ($kind in 'Remediations', 'PlatformScripts', 'Win32Apps') {
            $experiments[$kind] = @($experiments[$kind] | Where-Object {
                    $candidate = $_.Name
                    @($Name | Where-Object { $candidate -like $_ }).Count -gt 0
                })
        }
    }

    # Group containing just the test device
    $group = (Invoke-MgGraphRequest GET ("/v1.0/groups?`$filter=displayName eq " +
        "'$GroupName'")).value | Select-Object -First 1
    if (-not $group -and $PSCmdlet.ShouldProcess($GroupName, 'Create group')) {
        $group = Invoke-MgGraphRequest POST '/v1.0/groups' -Body @{
            displayName     = $GroupName
            mailEnabled     = $false
            mailNickname    = ($GroupName -replace '[^A-Za-z0-9]', '')
            securityEnabled = $true
            description     = 'IntuneScriptLab validation target. Safe to delete.'
        }
    }
    $device = if ($SkipDeviceMember) { $null }
    else {
        (Invoke-MgGraphRequest GET ("/v1.0/devices?`$filter=deviceId eq " +
            "'$AzureADDeviceId'&`$select=id,displayName")).value | Select-Object -First 1
    }
    if (-not $device -and -not $SkipDeviceMember) { throw "No Entra device with deviceId $AzureADDeviceId" }
    # A just-created group can 404 for a few seconds while Entra replicates it
    for ($attempt = 1; $device; $attempt++) {
        try {
            $members = (Invoke-MgGraphRequest GET "/v1.0/groups/$($group.id)/members?`$select=id").value.id
            if ($device.id -notin $members -and $PSCmdlet.ShouldProcess($device.displayName,
                "Add to $GroupName")) {
                Invoke-MgGraphRequest POST "/v1.0/groups/$($group.id)/members/`$ref" -Body @{
                    '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$($device.id)"
                }
            }
            break
        }
        catch {
            if ($attempt -ge 6) { throw }
            Write-Verbose "Group not ready (attempt $attempt): $($_.Exception.Message)"
            Start-Sleep -Seconds 10
        }
    }
    $target = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $group.id }

    $existingRem = (Get-AllGraphItem ('/beta/deviceManagement/deviceHealthScripts?$select=id,' +
        'displayName')).displayName
    foreach ($exp in $experiments.Remediations) {
        $name = $prefix + $exp.Name
        if ($name -in $existingRem) {
            Write-Information -InformationAction Continue -MessageData "Exists, skipping: $name"
            continue
        }
        $detection = ConvertTo-ScriptContent -Body $exp.Detection -Bom ([bool]$exp.Bom) -PadKB ([int]$exp.PadKB)
        $body = @{
            displayName            = $name
            description            = "$($exp.Question) | detectionSha256=$($detection.Sha256)"
            publisher              = 'IntuneScriptLab'
            enforceSignatureCheck  = $false
            detectionScriptContent = $detection.Base64
        }
        # A detect-only remediation is one created without a remediation script. The assignment's
        # runRemediationScript only reflects whether one was uploaded: set to false on a policy that
        # has a remediation script, it changed nothing (REM-DETECTONLY, rounds 6 and 7)
        if (-not $exp.DetectOnly) {
            $remediation = ConvertTo-ScriptContent -Body $exp.Remediation -Bom ([bool]$exp.Bom)
            $body.remediationScriptContent = $remediation.Base64
        }
        if ($exp.ContainsKey('RunAs32Bit')) { $body.runAs32Bit = $exp.RunAs32Bit }
        if ($exp.ContainsKey('RunAsAccount')) { $body.runAsAccount = $exp.RunAsAccount }
        if (-not $PSCmdlet.ShouldProcess($name, 'Create remediation')) { continue }

        $schedule = ConvertTo-RemediationSchedule -Schedule $exp.Schedule
        $policy = Invoke-MgGraphRequest POST '/beta/deviceManagement/deviceHealthScripts' -Body $body
        Invoke-MgGraphRequest POST "/beta/deviceManagement/deviceHealthScripts/$($policy.id)/assign" -Body @{
            deviceHealthScriptAssignments = @(@{
                    target               = $target
                    runRemediationScript = -not [bool]$exp.DetectOnly
                    runSchedule          = $schedule
                })
        }
        Write-Information -InformationAction Continue -MessageData (
            "Created remediation $name (runAs32Bit=$($policy.runAs32Bit), " +
            "runAsAccount=$($policy.runAsAccount), schedule=$($schedule.'@odata.type' -replace '.*\.', ''))")
    }

    $existingPs = (Get-AllGraphItem ('/beta/deviceManagement/deviceManagementScripts?$select=id,' +
        'displayName')).displayName
    foreach ($exp in $experiments.PlatformScripts) {
        $name = $prefix + $exp.Name
        if ($name -in $existingPs) {
            Write-Information -InformationAction Continue -MessageData "Exists, skipping: $name"
            continue
        }
        $content = ConvertTo-ScriptContent -Body $exp.Script -Bom ([bool]$exp.Bom) -PadKB ([int]$exp.PadKB)
        $body = @{
            displayName           = $name
            description           = "$($exp.Question) | sha256=$($content.Sha256)"
            fileName              = "$name.ps1"
            enforceSignatureCheck = $false
            scriptContent         = $content.Base64
        }
        if ($exp.ContainsKey('RunAs32Bit')) { $body.runAs32Bit = $exp.RunAs32Bit }
        if ($exp.ContainsKey('RunAsAccount')) { $body.runAsAccount = $exp.RunAsAccount }
        if (-not $PSCmdlet.ShouldProcess($name, 'Create platform script')) { continue }

        $policy = Invoke-MgGraphRequest POST '/beta/deviceManagement/deviceManagementScripts' -Body $body
        Invoke-MgGraphRequest POST "/beta/deviceManagement/deviceManagementScripts/$($policy.id)/assign" -Body @{
            deviceManagementScriptAssignments = @(@{ target = $target })
        }
        Write-Information -InformationAction Continue -MessageData (
            "Created platform script $name (runAs32Bit=$($policy.runAs32Bit), " +
            "runAsAccount=$($policy.runAsAccount))")
    }

    if ($experiments.Win32Apps) { Invoke-DeployWin32 -Experiments $experiments.Win32Apps -Target $target }
}

function Invoke-DeployWin32 {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][array]$Experiments, [Parameter(Mandatory)][hashtable]$Target)

    . (Join-Path -Path $PSScriptRoot -ChildPath 'Win32Content.ps1')
    if (-not (Test-Path -Path $IntuneWinAppUtilPath)) {
        # Microsoft's tool is not in the repo; fetch it and refuse anything not signed by Microsoft
        $null = New-Item -ItemType Directory -Path (Split-Path -Path $IntuneWinAppUtilPath -Parent) -Force
        $downloadMessage = "Downloading IntuneWinAppUtil.exe to $IntuneWinAppUtilPath"
        Write-Information -InformationAction Continue -MessageData $downloadMessage
        $toolUri = 'https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/raw/master/IntuneWinAppUtil.exe'
        Invoke-WebRequest -Uri $toolUri -OutFile $IntuneWinAppUtilPath
    }
    $signature = Get-AuthenticodeSignature -FilePath $IntuneWinAppUtilPath
    $signedByMicrosoft = $signature.SignerCertificate.Subject -match 'O=Microsoft Corporation'
    if ($signature.Status -ne 'Valid' -or -not $signedByMicrosoft) {
        throw ("IntuneWinAppUtil.exe at $IntuneWinAppUtilPath is not validly signed by Microsoft " +
            "($($signature.Status)); refusing to run it")
    }

    # One package for every app: install.ps1 = param block + probe + body
    $build = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath "ISL-Win32-$([guid]::NewGuid().ToString('N'))"
    $source = New-Item -ItemType Directory -Path (Join-Path -Path $build -ChildPath 'Source') -Force
    $probe = Get-Content -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Probe.ps1') -Raw
    # .Replace, not -replace: the probe text contains `$_`, which a regex replacement would expand
    $installPath = Join-Path -Path $PSScriptRoot -ChildPath 'Win32Install.ps1'
    $install = (Get-Content -Path $installPath -Raw).Replace('# --PROBE--', $probe)
    # A mis-spliced script can still parse (param( becomes a command), so check the param block survived
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($install, [ref]$null, [ref]$errors)
    if ($errors -or -not $ast.ParamBlock -or $ast.ParamBlock.Parameters.Count -ne 2) {
        throw ("Composed install.ps1 is malformed: $($errors.Message -join '; ') " +
            "paramBlock=$($null -ne $ast.ParamBlock)")
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
    $existingApps = @(Get-AllGraphItem $win32Query)
    $existing = $existingApps.displayName
    $appIds = @{}
    foreach ($known in $existingApps) { $appIds[$known.displayName] = $known.id }
    $relationships = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($exp in $Experiments) {
        $name = $prefix + $exp.Name
        if ($name -in $existing) {
            Write-Information -InformationAction Continue -MessageData "Exists, skipping: $name"
            continue
        }
        # An MSI experiment gets its own package built from the downloaded installer; Intune's
        # metadata (product code, version, upgrade code) comes out of the package XML
        $content = $scriptContent
        if ($exp.Package) {
            $content = Get-MsiPackageContent -Package $exp.Package -Build $build -Cache $packages
        }
        # Script rules get the probe header through the encoder; file, registry and product code rules
        # are passed through as specified (GraphRules.ps1)
        if ($content.MsiInformation -and -not $exp.Detection -and -not $exp.DetectionRules) {
            # The portal derives the MSI detection from the package; do the same
            $exp = @{} + $exp
            $exp.DetectionRules = @(@{ Type = 'ProductCode'; ProductCode = $content.MsiInformation.productCode })
        }
        $rules = Get-Win32AppRuleSet -Experiment $exp -Encode {
            param($Body, $Bom) (ConvertTo-ScriptContent -Body $Body -Bom $Bom).Base64
        }
        $sha = if ($exp.Detection) {
            " | detectionSha256=$((ConvertTo-ScriptContent -Body $exp.Detection -Bom ([bool]$exp.Bom)).Sha256)"
        }
        else { '' }
        $intent = if ($exp.Intent) { $exp.Intent } else { 'required' }
        $runAs = if ($exp.InstallContext) { $exp.InstallContext } else { 'system' }
        $installCommand = if ($exp.InstallCommand) { $exp.InstallCommand }
        elseif ($content.MsiInformation) { "msiexec /i `"$($content.SetupFile)`" /qn" }
        else { "powershell.exe -ExecutionPolicy Bypass -File install.ps1 -Experiment $($exp.Name)" }
        $uninstallCommand = if ($exp.UninstallCommand) { $exp.UninstallCommand }
        elseif ($content.MsiInformation) { "msiexec /x `"$($content.MsiInformation.productCode)`" /qn" }
        else { "powershell.exe -ExecutionPolicy Bypass -File install.ps1 -Experiment $($exp.Name) -Uninstall" }
        $body = @{
            '@odata.type'                  = '#microsoft.graph.win32LobApp'
            displayName                    = $name
            description                    = "$($exp.Question)$sha"
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
        # Base requirements (OS release, architecture, disk, memory, CPU) as the portal's Requirements page
        # sets them: keys are the Graph property names
        if ($exp.Requirements) {
            foreach ($key in @($exp.Requirements.Keys)) { $body[$key] = $exp.Requirements[$key] }
        }
        # An assignment filter, created on first use and named after the experiment
        $assignTarget = @{} + $Target
        if ($exp.Filter) {
            $filterId = Get-AssignmentFilterId -DisplayName "$prefix$($exp.Name)" -Rule $exp.Filter.Rule
            $assignTarget.deviceAndAppManagementAssignmentFilterId = $filterId
            $assignTarget.deviceAndAppManagementAssignmentFilterType = if ($exp.Filter.Mode) { $exp.Filter.Mode }
            else { 'include' }
        }
        $ruleCount = @($rules).Count
        if (-not $PSCmdlet.ShouldProcess($name, "Create Win32 app ($intent, $ruleCount rules)")) { continue }

        # One rejected rule must not end the round: Graph's answer is the finding, the rest still deploys
        try {
            $app = Invoke-MgGraphRequest POST '/beta/deviceAppManagement/mobileApps' -Body $body
            $appIds[$name] = $app.id
            Publish-Win32AppContent -AppId $app.id -Content $content
            # A dependency child is created but not assigned: Intune is supposed to install it for the parent
            if (-not ($exp.ContainsKey('Assign') -and -not $exp.Assign)) {
                Invoke-MgGraphRequest POST "/beta/deviceAppManagement/mobileApps/$($app.id)/assign" -Body @{
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
            if ($exp.DependsOn) {
                $relationships.Add(@{ App = $name; Target = "$prefix$($exp.DependsOn.App)"; Relationship = @{
                        '@odata.type' = '#microsoft.graph.mobileAppDependency'
                        dependencyType = if ($exp.DependsOn.Type) { $exp.DependsOn.Type } else { 'autoInstall' }
                    } })
            }
            if ($exp.Supersedes) {
                $relationships.Add(@{ App = $name; Target = "$prefix$($exp.Supersedes.App)"; Relationship = @{
                        '@odata.type'    = '#microsoft.graph.mobileAppSupersedence'
                        supersedenceType = if ($exp.Supersedes.Type) { $exp.Supersedes.Type } else { 'update' }
                    } })
            }
            $createdMessage = "Created Win32 app $name ($intent, $runAs, $(@($rules).Count) rules)"
            Write-Information -InformationAction Continue -MessageData $createdMessage
        }
        catch {
            Write-Warning ("Skipping $name after a Graph error (an app created without content or " +
                "assignment is left behind; Remove clears it): $($_.Exception.Message)")
        }
    }

    # Relationships need both apps to exist, so they are set once every app of the round is created
    foreach ($item in $relationships) {
        if (-not $appIds[$item.App] -or -not $appIds[$item.Target]) {
            Write-Warning "Relationship $($item.App) -> $($item.Target) skipped: an app is missing"
            continue
        }
        $relationship = @{ targetId = $appIds[$item.Target] } + $item.Relationship
        try {
            $uri = "/beta/deviceAppManagement/mobileApps/$($appIds[$item.App])/updateRelationships"
            Invoke-MgGraphRequest POST $uri -Body @{ relationships = @($relationship) }
            Write-Information -InformationAction Continue -MessageData ("Related $($item.App) -> " +
                "$($item.Target) ($($relationship['@odata.type'] -replace '.*\.', ''))")
        }
        catch {
            Write-Warning "Relationship $($item.App) -> $($item.Target) failed: $($_.Exception.Message)"
        }
    }
}

function Get-AssignmentFilterId {
    # A device assignment filter for Windows, reused by name across deploys
    param([Parameter(Mandatory)][string]$DisplayName, [Parameter(Mandatory)][string]$Rule)
    $existing = Get-AllGraphItem '/beta/deviceManagement/assignmentFilters?$select=id,displayName' |
        Where-Object { $_.displayName -eq $DisplayName } | Select-Object -First 1
    if ($existing) { return $existing.id }
    $filter = Invoke-MgGraphRequest POST '/beta/deviceManagement/assignmentFilters' -Body @{
        displayName                    = $DisplayName
        description                    = 'IntuneScriptLab validation filter. Safe to delete.'
        platform                       = 'windows10AndLater'
        rule                           = $Rule
        assignmentFilterManagementType = 'devices'
        roleScopeTags                  = @('0')
    }
    Write-Information -InformationAction Continue -MessageData "Created assignment filter $DisplayName ($Rule)"
    $filter.id
}

function Get-MsiPackageContent {
    # Downloads an installer once into Tools\, packages it with IntuneWinAppUtil and returns the content
    # object (with msiInformation from the package XML); the same package is reused across experiments
    param([Parameter(Mandatory)][hashtable]$Package, [Parameter(Mandatory)][string]$Build,
        [Parameter(Mandatory)][hashtable]$Cache)
    if ($Cache.ContainsKey($Package.FileName)) { return $Cache[$Package.FileName] }
    $tools = Split-Path -Path $IntuneWinAppUtilPath -Parent
    $installer = Join-Path -Path $tools -ChildPath $Package.FileName
    if (-not (Test-Path -Path $installer)) {
        Write-Information -InformationAction Continue -MessageData "Downloading $($Package.Url)"
        Invoke-WebRequest -Uri $Package.Url -OutFile $installer
    }
    if ($Package.Sha256) {
        $actual = (Get-FileHash -Path $installer -Algorithm SHA256).Hash
        if ($actual -ne $Package.Sha256) {
            throw "$($Package.FileName) hash $actual does not match $($Package.Sha256)"
        }
    }
    $source = New-Item -ItemType Directory -Path (Join-Path -Path $Build -ChildPath $Package.FileName) -Force
    Copy-Item -Path $installer -Destination $source
    $packageSplat = @{
        ToolPath     = $IntuneWinAppUtilPath
        SourceFolder = $source
        SetupFile    = $Package.FileName
        OutputFolder = Join-Path -Path $Build -ChildPath "Package-$($Package.FileName)"
    }
    $built = New-IntuneWinPackage @packageSplat
    $content = Get-IntuneWinContent -PackagePath $built.FullName -WorkFolder $source
    Write-Information -InformationAction Continue -MessageData ("Packaged $($Package.FileName): " +
        "$($content.UnencryptedSize) bytes, product $($content.MsiInformation.productCode) " +
        "$($content.MsiInformation.productVersion)")
    $Cache[$Package.FileName] = $content
    $content
}

function Invoke-Prepare {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if ($PSCmdlet.ShouldProcess("VM $VmId", 'Create C:\ProgramData\IntuneScriptLab with user write access')) {
        Invoke-GuestPowerShell -Script @'
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
        $fixtures = Get-Content -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures.ps1') -Raw
        Invoke-GuestScriptFile -Script $fixtures -RemoteName 'fixtures.ps1' -TimeoutSeconds 300
    }
}

function Invoke-Trigger {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if ($PSCmdlet.ShouldProcess("VM $VmId", 'Restart IntuneManagementExtension')) {
        Invoke-GuestPowerShell -Script ('Restart-Service -Name IntuneManagementExtension -Force; (Get-Service ' +
            'IntuneManagementExtension).Status')
    }
}

function Invoke-Collect {
    $remediations = foreach ($p in Get-AllGraphItem '/beta/deviceManagement/deviceHealthScripts') {
        if (-not $p.displayName.StartsWith($prefix)) { continue }
        [ordered]@{
            Name         = $p.displayName
            Id           = $p.id
            Description  = $p.description
            RunAs32Bit   = $p.runAs32Bit
            RunAsAccount = $p.runAsAccount
            RunStates    = Get-AllGraphItem "/beta/deviceManagement/deviceHealthScripts/$($p.id)/deviceRunStates"
        }
    }
    $platform = foreach ($p in Get-AllGraphItem '/beta/deviceManagement/deviceManagementScripts') {
        if (-not $p.displayName.StartsWith($prefix)) { continue }
        [ordered]@{
            Name         = $p.displayName
            Id           = $p.id
            Description  = $p.description
            RunAs32Bit   = $p.runAs32Bit
            RunAsAccount = $p.runAsAccount
            RunStates    = Get-AllGraphItem ("/beta/deviceManagement/deviceManagementScripts/" +
                "$($p.id)/deviceRunStates")
        }
    }
    $apps = @(Get-AllGraphItem ("/beta/deviceAppManagement/mobileApps?" +
            "`$filter=isof('microsoft.graph.win32LobApp')") |
        Where-Object { $_.displayName.StartsWith($prefix) })
    if ($AppName) {
        $apps = @($apps | Where-Object {
                $candidate = $_.displayName.Substring($prefix.Length)
                @($AppName | Where-Object { $candidate -like $_ }).Count -gt 0
            })
    }
    $win32 = foreach ($a in $apps) {
        [ordered]@{
            Name          = $a.displayName
            Id            = $a.id
            Description   = $a.description
            Rules         = @($a.rules |
                ForEach-Object {
                    $rule = [ordered]@{}
                    foreach ($k in ($_.Keys | Sort-Object)) { if ($k -ne 'scriptContent') { $rule[$k] = $_[$k] } }
                    $rule
                })
            Intent        = @((Get-AllGraphItem ("/beta/deviceAppManagement/mobileApps/$($a.id)/" +
                        'assignments')).intent)
            InstallStatus = @(Get-Win32InstallStatusReport -AppId $a.id |
                    Select-Object DeviceName, UserPrincipalName, AppInstallState_loc, AppInstallStateDetails_loc,
                        HexErrorCode, LastModifiedDateTime)
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
    $policyIds = @($remediations.Id) + @($platform.Id) | Where-Object { $_ }
    # A nested function's $PSBoundParameters is its own; an unbound [datetime] is MinValue
    $sinceText = if ($Since -gt [datetime]::MinValue) { $Since.ToUniversalTime().ToString('o') } else { '' }
    $deviceScript = $deviceScript.Replace('--POLICYIDS--', ($policyIds -join '|')).Replace('--SINCE--', $sinceText)
    $summary = Invoke-GuestScriptFile -Script $deviceScript -TimeoutSeconds 1500 -Detach
    if ("$summary" -notmatch '^\s*(\d+) ([0-9A-Fa-f]{64})\s*$') {
        throw "The device collect script returned no payload size and hash ('$summary'); see the warning above"
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
    } | ConvertTo-Json -Depth 12 | Set-Content -Path $file -Encoding utf8
    Write-Information -InformationAction Continue -MessageData "Results written to $file"
    $file
}

function Invoke-Remove {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $win32Query = "/beta/deviceAppManagement/mobileApps?`$filter=isof('microsoft.graph.win32LobApp')" +
        "&`$select=id,displayName"
    foreach ($a in Get-AllGraphItem $win32Query) {
        if ($a.displayName.StartsWith($prefix) -and $PSCmdlet.ShouldProcess($a.displayName, 'Delete Win32 app')) {
            Invoke-MgGraphRequest DELETE "/beta/deviceAppManagement/mobileApps/$($a.id)"
        }
    }
    foreach ($kind in 'deviceHealthScripts', 'deviceManagementScripts') {
        foreach ($p in Get-AllGraphItem "/beta/deviceManagement/$kind`?`$select=id,displayName") {
            if ($p.displayName.StartsWith($prefix) -and $PSCmdlet.ShouldProcess($p.displayName, 'Delete')) {
                Invoke-MgGraphRequest DELETE "/beta/deviceManagement/$kind/$($p.id)"
            }
        }
    }
    foreach ($f in Get-AllGraphItem '/beta/deviceManagement/assignmentFilters?$select=id,displayName') {
        if ($f.displayName.StartsWith($prefix) -and $PSCmdlet.ShouldProcess($f.displayName, 'Delete filter')) {
            Invoke-MgGraphRequest DELETE "/beta/deviceManagement/assignmentFilters/$($f.id)"
        }
    }
    $group = (Invoke-MgGraphRequest GET ("/v1.0/groups?`$filter=displayName eq " +
        "'$GroupName'")).value | Select-Object -First 1
    if ($group -and $PSCmdlet.ShouldProcess($GroupName, 'Delete group')) {
        Invoke-MgGraphRequest DELETE "/v1.0/groups/$($group.id)"
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
