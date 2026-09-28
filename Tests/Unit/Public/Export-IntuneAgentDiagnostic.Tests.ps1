#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The diagnostic package over a fake log folder: the zip holds the logs, the device facts, the
    registry text (or a note that it was skipped), the parsed events and timelines, and a manifest;
    an existing zip is refused without -Force.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    function script:New-CmTraceLine {
        param([string]$Message, [string]$Time, [string]$Date = '9-25-2026', [int]$Type = 1,
            [string]$Component = 'HealthScripts', [int]$Thread = 4)
        "<![LOG[$Message]LOG]!><time=`"$Time`" date=`"$Date`" component=`"$Component`" context=`"`" " +
        "type=`"$Type`" thread=`"$Thread`" file=`"`">"
    }
    function script:Get-ZipEntry {
        param([string]$Zip)
        $archive = [System.IO.Compression.ZipFile]::OpenRead($Zip)
        try { @($archive.Entries | ForEach-Object { $_.FullName }) } finally { $archive.Dispose() }
    }
    function script:Read-ZipEntry {
        param([string]$Zip, [string]$Name)
        $archive = [System.IO.Compression.ZipFile]::OpenRead($Zip)
        try {
            $entry = $archive.Entries | Where-Object FullName -eq $Name
            $reader = [System.IO.StreamReader]::new($entry.Open())
            try { $reader.ReadToEnd() } finally { $reader.Dispose() }
        }
        finally { $archive.Dispose() }
    }
    $script:Policy = 'bbf7e139-fe9d-4783-80df-627b8e084059'
    $script:Logs = Join-Path $TestDrive 'Logs'
    $null = New-Item -ItemType Directory -Path $script:Logs -Force
    $lines = @(
        New-CmTraceLine -Time '08:45:14.0000000' -Message ("[HS] Runner: script $($script:Policy) will try " +
            'to execute now.')
        New-CmTraceLine -Time '08:45:26.0000000' -Message ('[HS] the pre-remdiation detection script compliance ' +
            "result for $($script:Policy) is False")
        New-CmTraceLine -Time '08:45:27.0000000' -Message 'noise'
    )
    [System.IO.File]::WriteAllText((Join-Path $script:Logs 'HealthScripts.log'), (($lines -join "`r`n") + "`r`n"))
    $executorSplat = @{
        Time = '08:45:25.0000000'; Message = 'Powershell exit code is 1'; Component = 'AgentExecutor'
    }
    $executorLine = New-CmTraceLine @executorSplat
    [System.IO.File]::WriteAllText((Join-Path $script:Logs 'AgentExecutor.log'), "$executorLine`r`n")
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Export-IntuneAgentDiagnostic' -Tag 'Unit', 'Public' {

    Context 'Core Functionality' {
        BeforeAll {
            $script:Zip = Join-Path $TestDrive 'out\diag'
            $script:Result = Export-IntuneAgentDiagnostic -Path $script:Zip -LogPath $script:Logs -SkipRegistry
            $script:Entries = Get-ZipEntry -Zip $script:Result.Path
        }

        It 'writes the zip, adds the extension and describes the package' {
            $script:Result.PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.Diagnostic'
            $script:Result.Path | Should-BeLikeString '*\out\diag.zip'
            Test-Path -LiteralPath $script:Result.Path | Should-BeTrue
            $script:Result.Logs | Should-Be 2
            $script:Result.Registry | Should-BeFalse
            $script:Result.Timeline | Should-BeTrue
            $script:Result.Files | Should-Be $script:Entries.Count
            $script:Result.SizeBytes | Should-BeGreaterThan 0
        }

        It 'holds the logs, the device facts, the timelines and a manifest' {
            $script:Entries | Should-ContainCollection 'Logs/HealthScripts.log'
            $script:Entries | Should-ContainCollection 'Logs/AgentExecutor.log'
            $script:Entries | Should-ContainCollection 'Device/system.txt'
            $script:Entries | Should-ContainCollection 'Timeline/events.csv'
            $script:Entries | Should-ContainCollection 'Timeline/timelines.csv'
            $script:Entries | Should-ContainCollection 'Manifest.txt'
            @($script:Entries | Where-Object { $_ -like 'Registry/*' }).Count | Should-Be 0
        }

        It 'copies the logs byte for byte and parses them into events and timelines' {
            $copied = Read-ZipEntry -Zip $script:Result.Path -Name 'Logs/HealthScripts.log'
            $copied | Should-Be ([System.IO.File]::ReadAllText((Join-Path $script:Logs 'HealthScripts.log')))
            $events = Read-ZipEntry -Zip $script:Result.Path -Name 'Timeline/events.csv' | ConvertFrom-Csv
            @($events).Count | Should-Be 3
            @($events.Event | Sort-Object) |
                Should-BeCollection @('DetectionResult', 'ExecutorExit', 'RemediationStart')
            $timelines = Read-ZipEntry -Zip $script:Result.Path -Name 'Timeline/timelines.csv' | ConvertFrom-Csv
            @($timelines).Count | Should-Be 1
            $timelines[0].Id | Should-Be $script:Policy
            $timelines[0].Outcome | Should-Be 'DetectionResult pre False'
        }

        It 'records the device facts and the manifest' {
            $system = Read-ZipEntry -Zip $script:Result.Path -Name 'Device/system.txt'
            $system | Should-BeLikeString "*Computer: $env:COMPUTERNAME*PowerShell: $($PSVersionTable.PSVersion)*"
            $system | Should-BeLikeString '*IntuneScriptLab: *'
            $manifest = Read-ZipEntry -Zip $script:Result.Path -Name 'Manifest.txt'
            $manifest | Should-BeLikeString 'IntuneScriptLab diagnostic package*Logs: 2 file(s)*Registry: skipped*'
            $manifest | Should-BeLikeString '*Timeline: 3 event(s), 1 timeline(s)*'
        }
    }

    Context 'Options' {
        It 'refuses an existing zip without -Force and overwrites it with -Force' {
            $zip = Join-Path $TestDrive 'twice.zip'
            $null = Export-IntuneAgentDiagnostic -Path $zip -LogPath $script:Logs -SkipRegistry -SkipTimeline
            { Export-IntuneAgentDiagnostic -Path $zip -LogPath $script:Logs -SkipRegistry -SkipTimeline } |
                Should-Throw -ExceptionMessage '*exists; use -Force*'
            $againSplat = @{ Path = $zip; LogPath = $script:Logs; SkipRegistry = $true; SkipTimeline = $true }
            $again = Export-IntuneAgentDiagnostic @againSplat -Force
            $again.Timeline | Should-BeFalse
            Get-ZipEntry -Zip $zip | Should-NotContainCollection 'Timeline/events.csv'
        }

        It 'dumps the registry keys it knows, noting the ones this machine lacks' {
            $zip = Join-Path $TestDrive 'registry.zip'
            $result = Export-IntuneAgentDiagnostic -Path $zip -LogPath $script:Logs -SkipTimeline
            $result.Registry | Should-BeTrue
            $entries = Get-ZipEntry -Zip $zip
            $entries | Should-ContainCollection 'Registry/IntuneManagementExtension.txt'
            $entries | Should-ContainCollection 'Registry/Autopilot.txt'
            $text = Read-ZipEntry -Zip $zip -Name 'Registry/Autopilot.txt'
            $text | Should-BeLikeString '*Provisioning\Diagnostics\AutoPilot*'
        }

        It 'warns about a missing log folder and still writes the package' {
            $zip = Join-Path $TestDrive 'nologs.zip'
            $warnings = @()
            $missingSplat = @{ Path = $zip; LogPath = (Join-Path $TestDrive 'nope'); SkipRegistry = $true }
            $result = Export-IntuneAgentDiagnostic @missingSplat -WarningVariable warnings 3>$null
            $result.Logs | Should-Be 0
            $result.Timeline | Should-BeFalse
            "$($warnings[0])" | Should-BeLikeString 'Log folder not found*'
            Get-ZipEntry -Zip $zip | Should-ContainCollection 'Manifest.txt'
        }
    }
}
