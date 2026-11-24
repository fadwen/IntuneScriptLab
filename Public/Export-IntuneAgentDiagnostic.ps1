function Export-IntuneAgentDiagnostic {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Packs the agent's logs, its registry state and the parsed timelines into one zip for a ticket.
    #>
    [CmdletBinding(SupportsShouldProcess)]
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
        $recordSplat = @{
            Message = "$zip exists; use -Force to overwrite it"
            ErrorId = 'DiagnosticPackageExists'
            Category = [System.Management.Automation.ErrorCategory]::ResourceExists
            TargetObject = $zip
            ExceptionType = [System.IO.IOException]
        }
        $PSCmdlet.ThrowTerminatingError((New-IslErrorRecord @recordSplat))
    }
    if (-not $PSCmdlet.ShouldProcess($zip, 'Write the diagnostic package')) {
        return
    }
    if (-not $LogPath) {
        $programData = if ($env:ProgramData) { $env:ProgramData } else { 'C:\ProgramData' }
        $LogPath = Join-Path -Path $programData -ChildPath 'Microsoft\IntuneManagementExtension\Logs'
    }
    $stagingName = "IntuneScriptLab-diag-$([guid]::NewGuid().ToString('N'))"
    $staging = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath $stagingName
    $manifest = [System.Collections.Generic.List[string]]::new()

    try {
        $null = New-Item -ItemType Directory -Path $staging -Force @script:IslInternal

        # Logs
        $logFiles = @()
        if (Test-Path -LiteralPath $LogPath -PathType Container) {
            $logFiles = @(Get-ChildItem -LiteralPath $LogPath -Filter '*.log' -File)
            $logFolder = Join-Path -Path $staging -ChildPath 'Logs'
            $null = New-Item -ItemType Directory -Path $logFolder -Force @script:IslInternal
            foreach ($file in $logFiles) {
                $destination = Join-Path -Path $logFolder -ChildPath $file.Name
                # A log the agent holds open is copied through a shared-read stream
                Copy-IslSharedFile -Source $file.FullName -Destination $destination @script:IslInternal
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
        Write-IslTextFile -Root $staging -RelativePath 'Device\system.txt' -Line $system @script:IslInternal
        if (Get-Command -Name dsregcmd.exe -ErrorAction SilentlyContinue) {
            $joinState = @(& dsregcmd.exe /status 2>&1 | ForEach-Object { "$_" })
            $sectionSplat = @{ Root = $staging; RelativePath = 'Device\dsregcmd.txt'; Line = $joinState }
            Write-IslTextFile @sectionSplat @script:IslInternal
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
                $lines = @(Get-IslRegistryText -Key $entry.Key -Depth $entry.Depth)
                $sectionSplat = @{ Root = $staging; RelativePath = "Registry\$($entry.Name).txt"; Line = $lines }
                Write-IslTextFile @sectionSplat @script:IslInternal
            }
            $manifest.Add("Registry: $(($keys | ForEach-Object { $_.Name }) -join ', ')")
        }
        else { $manifest.Add('Registry: skipped') }

        # Timeline
        if (-not $SkipTimeline -and $logFiles.Count) {
            $timelineFolder = Join-Path -Path $staging -ChildPath 'Timeline'
            $null = New-Item -ItemType Directory -Path $timelineFolder -Force @script:IslInternal
            $events = @(Get-IntuneAgentLog -Path $LogPath -Log All | Where-Object Event)
            $iso = @{ Name = 'Time'; Expression = { $_.Time.ToString('o') } }
            $eventRows = $events | Select-Object -Property $iso, Log, Event, Detail, Id, Message
            $csvSplat = @{ NoTypeInformation = $true; Encoding = 'UTF8' }
            $eventsCsv = Join-Path -Path $timelineFolder -ChildPath 'events.csv'
            $eventRows | Export-Csv -LiteralPath $eventsCsv @csvSplat @script:IslInternal
            $timelines = @(Get-IntuneAgentTimeline -Path $LogPath -Log All)
            $timelineRows = $timelines | Select-Object -Property Id, Name, Kind,
            @{ Name = 'Started'; Expression = { $_.Started.ToString('o') } },
            @{ Name = 'Ended'; Expression = { $_.Ended.ToString('o') } },
            @{ Name = 'Duration'; Expression = { $_.Duration.ToString() } }, Runs, Outcome, Summary
            $timelinesCsv = Join-Path -Path $timelineFolder -ChildPath 'timelines.csv'
            $timelineRows | Export-Csv -LiteralPath $timelinesCsv @csvSplat @script:IslInternal
            $manifest.Add("Timeline: $($events.Count) event(s), $($timelines.Count) timeline(s)")
        }
        else { $manifest.Add('Timeline: skipped') }

        $manifest.Insert(0, "IntuneScriptLab diagnostic package, $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))")
        Write-IslTextFile -Root $staging -RelativePath 'Manifest.txt' -Line $manifest @script:IslInternal

        if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force @script:IslInternal }
        $zipFolder = Split-Path -Path $zip -Parent
        if ($zipFolder -and -not (Test-Path -LiteralPath $zipFolder)) {
            $null = New-Item -ItemType Directory -Path $zipFolder -Force @script:IslInternal
        }
        $entryCount = Compress-IslFolder -Folder $staging -Destination $zip @script:IslInternal
    }
    catch {
        # Whatever failed, the package is not complete: the command ends without a result
        $PSCmdlet.ThrowTerminatingError($_)
    }
    finally {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue @script:IslInternal
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
