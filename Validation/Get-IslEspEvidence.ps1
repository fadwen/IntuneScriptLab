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

Set-StrictMode -Version Latest
# Exception to ERR-01: the script collects what it can and goes on past a read that fails, so that
# one bad source does not cost the evidence of all the others. Under Windows PowerShell 5.1 the
# line that query.exe writes to the redirected error stream while nobody is signed in, as during
# the device phase of the page, becomes an error record, and a probe line that is not JSON fails
# ConvertFrom-Json; under 'Stop' either would end the script before it writes any JSON. The errors
# still reach stderr, which Invoke-LabGuestScript.ps1 shows as warnings.
$ErrorActionPreference = 'Continue'
$base = 'C:\ProgramData\IntuneScriptLab'
$result = [ordered]@{}
$result.CollectedUtc = (Get-Date).ToUniversalTime().ToString('o')
$result.Computer = $env:COMPUTERNAME
$result.Sessions = @(query user 2>$null | ForEach-Object { "$_" })

$probeFiles = Get-ChildItem -LiteralPath $base -Filter '*.jsonl' -ErrorAction SilentlyContinue |
    Where-Object Name -ne 'esp-state.jsonl'
$result.Probes = @(foreach ($file in $probeFiles) {
        foreach ($line in (Get-Content -LiteralPath $file.FullName)) {
            $record = $line | ConvertFrom-Json
            $record | Add-Member -NotePropertyName File -NotePropertyValue $file.BaseName -Force
            $record | Select-Object -Property File, Experiment, Phase, Time, User, SessionId, UserInteractive,
                Cwd, ParentName
        }
    })
$statePath = Join-Path -Path $base -ChildPath 'esp-state.jsonl'
$result.EspState = @(if (Test-Path -LiteralPath $statePath) {
        Get-Content -LiteralPath $statePath | ForEach-Object { $_ | ConvertFrom-Json }
    })
$result.Markers = @(Get-ChildItem -LiteralPath $base -Filter '*.installed' -ErrorAction SilentlyContinue |
        ForEach-Object { "$($_.Name) $($_.LastWriteTimeUtc.ToString('o'))" })


function ConvertTo-ValueLine {
    <#
    .SYNOPSIS
        Formats the values of one registry key as a single line of text.

    .DESCRIPTION
        Reads the values of the key and writes its path below the prefix, a colon, and the values
        as name=value pairs separated by semicolons. A key without values gives its path and
        nothing after the colon.

    .PARAMETER Path
        The registry key as a provider path, such as the PSPath of an item that Get-ChildItem
        returns. Read as a literal path.

    .PARAMETER Prefix
        The name of the key that the path is cut after, so that the line starts below it.

    .EXAMPLE
        ConvertTo-ValueLine -Path $key.PSPath -Prefix 'EnrollmentStatusTracking'

        One line for a key below EnrollmentStatusTracking, its path relative to that key.

    .INPUTS
        None.

    .OUTPUTS
        System.String.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Prefix
    )

    $item = Get-ItemProperty -LiteralPath $Path
    # Get-ItemProperty returns nothing for a key without values, and strict mode refuses a member of $null
    $values = ''
    if ($null -ne $item) {
        $values = ($item.PSObject.Properties |
                Where-Object { $_.Name -notlike 'PS*' } |
                ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ';'
    }
    "$($Path -replace ('.*' + [regex]::Escape($Prefix) + '\\?'), ''): $values"
}


$enrollments = Get-ChildItem -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue
$result.Enrollments = @(foreach ($enrollment in $enrollments) {
        $syncPath = Join-Path -Path $enrollment.PSPath -ChildPath 'FirstSync'
        $sync = Get-ItemProperty -LiteralPath $syncPath -ErrorAction SilentlyContinue
        if (-not $sync) { continue }
        $values = [ordered]@{ Enrollment = $enrollment.PSChildName }
        foreach ($property in ($sync.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' })) {
            $values[$property.Name] = "$($property.Value)"
        }
        [pscustomobject]$values
    })
$tracking = 'HKLM:\SOFTWARE\Microsoft\Windows\Autopilot\EnrollmentStatusTracking'
$result.EspTracking = @(Get-ChildItem -LiteralPath $tracking -Recurse -ErrorAction SilentlyContinue |
        ForEach-Object { ConvertTo-ValueLine -Path $_.PSPath -Prefix 'EnrollmentStatusTracking' })
$autopilotPath = 'HKLM:\SOFTWARE\Microsoft\Provisioning\Diagnostics\AutoPilot'
$result.AutopilotDiag = @(Get-ItemProperty -LiteralPath $autopilotPath -ErrorAction SilentlyContinue |
        Select-Object -Property * -ExcludeProperty PS* | ConvertTo-Json -Compress)

$logs = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
$keywords = 'ESP|Esp|EnrollmentStatus|Sidecar|ISL-ESP|policies|After filter|Blocking|block|OOBE|IsDeviceInOobe|' +
    'userless|Userless|DeviceSetup|AccountSetup|Enrollment|Autopilot|Flighting\] Key'
foreach ($log in 'IntuneManagementExtension', 'AppWorkload', 'HealthScripts', 'AgentExecutor') {
    $file = Get-ChildItem -LiteralPath $logs -Filter "$log*.log" -ErrorAction SilentlyContinue |
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
