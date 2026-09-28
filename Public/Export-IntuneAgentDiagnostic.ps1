function Export-IntuneAgentDiagnostic {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Packs the agent's logs, its registry state and the parsed timelines into one zip for a ticket.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.Diagnostic')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,

        [string]$LogPath,

        [switch]$SkipRegistry,

        [switch]$SkipTimeline,

        [switch]$Force
    )
    Write-Verbose "Starting $($MyInvocation.MyCommand.Name)"

    if ([System.IO.Path]::GetExtension($Path) -ne '.zip') { $Path = "$Path.zip" }
    $zip = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if ((Test-Path -LiteralPath $zip) -and -not $Force) {
        throw "$zip exists; use -Force to overwrite it"
    }
    if (-not $LogPath) {
        $programData = if ($env:ProgramData) { $env:ProgramData } else { 'C:\ProgramData' }
        $LogPath = Join-Path -Path $programData -ChildPath 'Microsoft\IntuneManagementExtension\Logs'
    }
    $stagingName = "IntuneScriptLab-diag-$([guid]::NewGuid().ToString('N'))"
    $staging = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath $stagingName
    $manifest = [System.Collections.Generic.List[string]]::new()
    $utf8 = [System.Text.UTF8Encoding]::new($false)

    function Write-Section {
        param([string]$Relative, [string[]]$Lines)
        $file = Join-Path -Path $staging -ChildPath $Relative
        $null = New-Item -ItemType Directory -Path (Split-Path -Path $file -Parent) -Force
        [System.IO.File]::WriteAllLines($file, [string[]]$Lines, $utf8)
    }

    # A log the agent holds open copies through a shared-read stream
    function Copy-SharedFile {
        param([string]$Source, [string]$Destination)
        $in = [System.IO.File]::Open($Source, 'Open', 'Read', 'ReadWrite')
        try {
            $out = [System.IO.File]::Create($Destination)
            try { $in.CopyTo($out) } finally { $out.Dispose() }
        }
        finally { $in.Dispose() }
    }

    # A registry key and its subkeys as "key" and "  name = value" lines
    function Get-RegistryText {
        param([string]$Key, [int]$Depth)
        if (-not (Test-Path -LiteralPath $Key)) { return @("$Key : not present") }
        $children = @(Get-ChildItem -LiteralPath $Key -Recurse -Depth $Depth -ErrorAction SilentlyContinue)
        $keys = @(Get-Item -LiteralPath $Key) + $children
        foreach ($item in $keys) {
            "[$($item.Name)]"
            $values = Get-ItemProperty -LiteralPath $item.PSPath -ErrorAction SilentlyContinue
            if (-not $values) { continue }
            foreach ($property in $values.PSObject.Properties) {
                if ($property.Name -like 'PS*') { continue }
                $text = if ($property.Value -is [byte[]]) { "byte[$($property.Value.Length)]" }
                else { "$($property.Value)" }
                if ($text.Length -gt 400) { $text = $text.Substring(0, 400) + '...' }
                "  $($property.Name) = $text"
            }
        }
    }

    # The staging folder as a zip with forward-slash entry names on every host (.NET Framework's
    # CreateFromDirectory writes backslashes)
    function Compress-Staging {
        param([string]$Folder, [string]$Destination)
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::Open($Destination, 'Create')
        $count = 0
        try {
            foreach ($file in (Get-ChildItem -LiteralPath $Folder -Recurse -File)) {
                $relative = $file.FullName.Substring($Folder.Length).TrimStart('\', '/') -replace '\\', '/'
                $null = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                    $archive, $file.FullName, $relative)
                $count++
            }
        }
        finally { $archive.Dispose() }
        $count
    }

    try {
        $null = New-Item -ItemType Directory -Path $staging -Force

        # Logs
        $logFiles = @()
        if (Test-Path -LiteralPath $LogPath -PathType Container) {
            $logFiles = @(Get-ChildItem -LiteralPath $LogPath -Filter '*.log' -File)
            $logFolder = Join-Path -Path $staging -ChildPath 'Logs'
            $null = New-Item -ItemType Directory -Path $logFolder -Force
            foreach ($file in $logFiles) {
                $destination = Join-Path -Path $logFolder -ChildPath $file.Name
                Copy-SharedFile -Source $file.FullName -Destination $destination
            }
            $manifest.Add("Logs: $($logFiles.Count) file(s) from $LogPath")
        }
        else {
            $manifest.Add("Logs: folder not found: $LogPath")
            Write-Warning "Log folder not found: $LogPath"
        }

        # Device
        $system = [System.Collections.Generic.List[string]]::new()
        $system.Add("Computer: $env:COMPUTERNAME")
        $system.Add("Collected: $((Get-Date).ToString('o')) ($([System.TimeZoneInfo]::Local.Id))")
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) { $system.Add("Windows: $($os.Caption) $($os.Version) $($os.OSArchitecture)") }
        $system.Add("PowerShell: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))")
        $system.Add("Process architecture: $env:PROCESSOR_ARCHITECTURE")
        $module = $MyInvocation.MyCommand.Module
        if ($module) { $system.Add("IntuneScriptLab: $($module.Version)") }
        $service = Get-Service -Name IntuneManagementExtension -ErrorAction SilentlyContinue
        $system.Add("Agent service: $(if ($service) { $service.Status } else { 'not installed' })")
        $agentFolder = Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'Microsoft Intune Management Extension'
        $agentExe = Join-Path -Path $agentFolder -ChildPath 'Microsoft.Management.Services.IntuneWindowsAgent.exe'
        if ($agentExe -and (Test-Path -LiteralPath $agentExe)) {
            $system.Add("Agent version: $((Get-Item -LiteralPath $agentExe).VersionInfo.FileVersion)")
        }
        Write-Section -Relative 'Device\system.txt' -Lines $system
        if (Get-Command -Name dsregcmd.exe -ErrorAction SilentlyContinue) {
            $joinState = @(& dsregcmd.exe /status 2>&1 | ForEach-Object { "$_" })
            Write-Section -Relative 'Device\dsregcmd.txt' -Lines $joinState
            $manifest.Add('Device: system.txt, dsregcmd.txt')
        }
        else { $manifest.Add('Device: system.txt (dsregcmd not available)') }

        # Registry
        if (-not $SkipRegistry) {
            $keys = @(
                @{ Name = 'IntuneManagementExtension'; Depth = 6
                    Key = 'HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension' }
                @{ Name = 'Enrollments'; Key = 'HKLM:\SOFTWARE\Microsoft\Enrollments'; Depth = 2 }
                @{ Name = 'EnrollmentStatusTracking'; Depth = 6
                    Key = 'HKLM:\SOFTWARE\Microsoft\Windows\Autopilot\EnrollmentStatusTracking' }
                @{ Name = 'Autopilot'; Depth = 1
                    Key = 'HKLM:\SOFTWARE\Microsoft\Provisioning\Diagnostics\AutoPilot' }
            )
            foreach ($entry in $keys) {
                $lines = @(Get-RegistryText -Key $entry.Key -Depth $entry.Depth)
                Write-Section -Relative "Registry\$($entry.Name).txt" -Lines $lines
            }
            $manifest.Add("Registry: $(($keys | ForEach-Object { $_.Name }) -join ', ')")
        }
        else { $manifest.Add('Registry: skipped') }

        # Timeline
        if (-not $SkipTimeline -and $logFiles.Count) {
            $timelineFolder = Join-Path -Path $staging -ChildPath 'Timeline'
            $null = New-Item -ItemType Directory -Path $timelineFolder -Force
            $events = @(Get-IntuneAgentLog -Path $LogPath -Log All | Where-Object Event)
            $iso = @{ Name = 'Time'; Expression = { $_.Time.ToString('o') } }
            $eventRows = $events | Select-Object -Property $iso, Log, Event, Detail, Id, Message
            $csvSplat = @{ NoTypeInformation = $true; Encoding = 'UTF8' }
            $eventsCsv = Join-Path -Path $timelineFolder -ChildPath 'events.csv'
            $eventRows | Export-Csv -LiteralPath $eventsCsv @csvSplat
            $timelines = @(Get-IntuneAgentTimeline -Path $LogPath -Log All)
            $timelineRows = $timelines | Select-Object -Property Id, Name, Kind,
            @{ Name = 'Started'; Expression = { $_.Started.ToString('o') } },
            @{ Name = 'Ended'; Expression = { $_.Ended.ToString('o') } },
            @{ Name = 'Duration'; Expression = { $_.Duration.ToString() } }, Runs, Outcome, Summary
            $timelinesCsv = Join-Path -Path $timelineFolder -ChildPath 'timelines.csv'
            $timelineRows | Export-Csv -LiteralPath $timelinesCsv @csvSplat
            $manifest.Add("Timeline: $($events.Count) event(s), $($timelines.Count) timeline(s)")
        }
        else { $manifest.Add('Timeline: skipped') }

        $manifest.Insert(0, "IntuneScriptLab diagnostic package, $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))")
        Write-Section -Relative 'Manifest.txt' -Lines $manifest

        if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
        $zipFolder = Split-Path -Path $zip -Parent
        if ($zipFolder -and -not (Test-Path -LiteralPath $zipFolder)) {
            $null = New-Item -ItemType Directory -Path $zipFolder -Force
        }
        $entryCount = Compress-Staging -Folder $staging -Destination $zip
    }
    finally {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Verbose "Completed $($MyInvocation.MyCommand.Name): $zip"
    [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.Diagnostic'
        Path       = $zip
        Files      = $entryCount
        Logs       = $logFiles.Count
        Registry   = -not $SkipRegistry
        Timeline   = (-not $SkipTimeline) -and $logFiles.Count -gt 0
        SizeBytes  = (Get-Item -LiteralPath $zip).Length
    }
}
