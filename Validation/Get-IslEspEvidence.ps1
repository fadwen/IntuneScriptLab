#Requires -Version 5.1

<#
    .SYNOPSIS
        Collects what a lab device recorded during its Enrollment Status Page run, as one JSON document.

    .DESCRIPTION
        Run on the device as SYSTEM after the page has closed (through Invoke-LabGuestScript.ps1 with
        -RemoteName Get-IslEspEvidence.ps1, or elevated at a console). Gathers:

        - every probe record the round-8 experiments wrote (C:\ProgramData\IntuneScriptLab\*.jsonl)
          with the launch context of each run, and the Write-EspState records that hold the page's
          state at the moment each script ran;
        - the marker files the shared Win32 install writes;
        - the FirstSync values of every enrollment (the page's skip flags, phase durations and sync
          state), the EnrollmentStatusTracking registry (the sidecar's tracked apps and their
          installation states, device and per-user) and its Diagnostics history;
        - the Autopilot diagnostics values;
        - the ESP-relevant lines of the agent's four logs, opened with shared access.

        The result feeds Findings.md ("The Enrollment Status Page"). Nothing is changed on the device.

    .EXAMPLE
        .\Invoke-LabGuestScript.ps1 -VmId 126 -ScriptPath .\Get-IslEspEvidence.ps1 -TimeoutSeconds 300 |
            Set-Content -Path .\Results\round8\esp-evidence.json

        Collects the evidence from VM 126 through the guest agent and keeps the JSON locally.

    .EXAMPLE
        $evidence = Get-Content .\Results\round8\esp-evidence.json | ConvertFrom-Json
        $evidence.Probes | Sort-Object Time | Format-Table Time, Experiment, Phase, User, SessionId

        The run order of every script during and after the page.

    .EXAMPLE
        $evidence.EspTracking | Where-Object { $_ -like '*InstallationState*' }

        The tracked apps and their final states, device and per-user.

    .INPUTS
        None.

    .OUTPUTS
        System.String. One JSON document on stdout.

    .NOTES
        Author: Jeffrey Stuhr. Windows PowerShell 5.1 compatible: the guest agent runs powershell.exe.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$base = 'C:\ProgramData\IntuneScriptLab'
$result = [ordered]@{}
$result.CollectedUtc = (Get-Date).ToUniversalTime().ToString('o')
$result.Computer = $env:COMPUTERNAME
$result.Sessions = @(query user 2>$null | ForEach-Object { "$_" })

$probeFiles = Get-ChildItem -Path $base -Filter '*.jsonl' -ErrorAction SilentlyContinue |
    Where-Object Name -ne 'esp-state.jsonl'
$result.Probes = @(foreach ($file in $probeFiles) {
        foreach ($line in (Get-Content -Path $file.FullName)) {
            $record = $line | ConvertFrom-Json
            $record | Add-Member -NotePropertyName File -NotePropertyValue $file.BaseName -Force
            $record | Select-Object -Property File, Experiment, Phase, Time, User, SessionId, UserInteractive,
                Cwd, ParentName
        }
    })
$statePath = Join-Path -Path $base -ChildPath 'esp-state.jsonl'
$result.EspState = @(if (Test-Path -Path $statePath) {
        Get-Content -Path $statePath | ForEach-Object { $_ | ConvertFrom-Json }
    })
$result.Markers = @(Get-ChildItem -Path $base -Filter '*.installed' -ErrorAction SilentlyContinue |
        ForEach-Object { "$($_.Name) $($_.LastWriteTimeUtc.ToString('o'))" })

function ConvertTo-ValueLine {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Prefix)
    $item = Get-ItemProperty -Path $Path
    $values = ($item.PSObject.Properties |
            Where-Object { $_.Name -notlike 'PS*' } |
            ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ';'
    "$($Path -replace ('.*' + [regex]::Escape($Prefix) + '\\?'), ''): $values"
}

$enrollments = Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue
$result.Enrollments = @(foreach ($enrollment in $enrollments) {
        $syncPath = Join-Path -Path $enrollment.PSPath -ChildPath 'FirstSync'
        $sync = Get-ItemProperty -Path $syncPath -ErrorAction SilentlyContinue
        if (-not $sync) { continue }
        $values = [ordered]@{ Enrollment = $enrollment.PSChildName }
        foreach ($property in ($sync.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' })) {
            $values[$property.Name] = "$($property.Value)"
        }
        [pscustomobject]$values
    })
$tracking = 'HKLM:\SOFTWARE\Microsoft\Windows\Autopilot\EnrollmentStatusTracking'
$result.EspTracking = @(Get-ChildItem -Path $tracking -Recurse -ErrorAction SilentlyContinue |
        ForEach-Object { ConvertTo-ValueLine -Path $_.PSPath -Prefix 'EnrollmentStatusTracking' })
$autopilotPath = 'HKLM:\SOFTWARE\Microsoft\Provisioning\Diagnostics\AutoPilot'
$result.AutopilotDiag = @(Get-ItemProperty -Path $autopilotPath -ErrorAction SilentlyContinue |
        Select-Object -Property * -ExcludeProperty PS* | ConvertTo-Json -Compress)

$logs = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
$keywords = 'ESP|Esp|EnrollmentStatus|Sidecar|ISL-ESP|policies|After filter|Blocking|block|OOBE|IsDeviceInOobe|' +
    'userless|Userless|DeviceSetup|AccountSetup|Enrollment|Autopilot|Flighting\] Key'
foreach ($log in 'IntuneManagementExtension', 'AppWorkload', 'HealthScripts', 'AgentExecutor') {
    $file = Get-ChildItem -Path $logs -Filter "$log*.log" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime | Select-Object -Last 1
    if (-not $file) { continue }
    $stream = [IO.File]::Open($file.FullName, 'Open', 'Read', 'ReadWrite')
    $reader = [IO.StreamReader]::new($stream)
    $text = $reader.ReadToEnd()
    $reader.Dispose()
    $stream.Dispose()
    $lines = $text -split "`r?`n" | Where-Object { $_ -match $keywords } | Select-Object -First 600
    $result["Log_$log"] = @($lines | ForEach-Object {
            if ($_ -match '<!\[LOG\[(.*?)\]LOG\]!><time="([^"]+)" date="([^"]+)"') {
                "$($Matches[3]) $($Matches[2]) $($Matches[1])"
            }
            else { $_ }
        })
}
$result | ConvertTo-Json -Depth 5
