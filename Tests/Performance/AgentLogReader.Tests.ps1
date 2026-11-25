#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }
#pester:no-shuffle

<#
    Get-IntuneAgentLog and Get-IntuneAgentTimeline on a generated HealthScripts.log: each remediation
    policy writes the five lines of one run, as the agent does, so a log of 10,000 lines holds 2,000
    runs. Each reader is measured once at a quarter of that and once at the whole: the time and the
    memory it holds against a limit with room for a slow runner, and the time at four times the
    lines against six times the time of the smaller log, which a reader that grows linearly stays
    well inside and one that grows with the square of the lines does not. Every measurement is
    written to the information stream as a MEASURE line, for the baselines of the performance gate.

    On a Windows 11 laptop, 20,000 lines took 5 to 6 seconds for the log reader and 6 to 11 seconds
    for the timeline, on PowerShell 7.6 and Windows PowerShell 5.1.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    function script:New-HealthScriptsLog {
        <#
        .SYNOPSIS
            Writes a HealthScripts.log of a number of remediation runs into a new folder.

        .DESCRIPTION
            Each run is the five lines the agent writes for one remediation policy: the schedule,
            the queued job, the start, the detection result and the new result, ten seconds apart
            from the run before, under a policy id of its own. The file is UTF-8 without a byte
            order mark with CRLF line endings, as the agent writes it.

        .PARAMETER Runs
            How many runs the log holds; it has five lines for each.

        .EXAMPLE
            New-HealthScriptsLog -Runs 500

            Returns the folder of a log of 2,500 lines.

        .INPUTS
            None.

        .OUTPUTS
            System.String. The folder that holds HealthScripts.log.
        #>
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [Parameter(Mandatory)]
            [int]$Runs
        )

        $folder = Join-Path $TestDrive "logs-$Runs"
        $null = New-Item -ItemType Directory -Path $folder -Force
        $start = [datetime]'2026-09-25T00:00:00'
        $builder = [System.Text.StringBuilder]::new()
        for ($run = 0; $run -lt $Runs; $run++) {
            $policy = [guid]::NewGuid().ToString()
            $runStart = $start.AddSeconds($run * 10)
            $messages = @(
                "[HS] inspect hourly schedule for policy ${policy}: UTC = False, Interval = 1, Time = "
                '[HS] Runner : Job is queued and will be scheduled to run at UTC 9/25/2026 8:45:14 AM.'
                "[HS] Runner: script $policy will try to execute now."
                "[HS] the pre-remdiation detection script compliance result for $policy is False"
                ('[HS] new result = {"PolicyId":"' + $policy + '","UserId":"00000000-0000-0000-0000-' +
                '000000000000","PolicyHash":null,"Result":4,"ResultDetails":"{}"}')
            )
            for ($index = 0; $index -lt $messages.Count; $index++) {
                $time = $runStart.AddSeconds($index).ToString('HH:mm:ss.fffffff')
                $line = "<![LOG[$($messages[$index])]LOG]!><time=`"$time`" date=`"9-25-2026`" " +
                "component=`"HealthScripts`" context=`"`" type=`"1`" thread=`"4`" file=`"`">"
                $null = $builder.Append($line).Append("`r`n")
            }
        }
        $path = Join-Path $folder 'HealthScripts.log'
        [System.IO.File]::WriteAllText($path, $builder.ToString(), [System.Text.UTF8Encoding]::new($false))
        $folder
    }

    function script:Measure-Reader {
        <#
        .SYNOPSIS
            Runs a log reader once and measures its time and the memory its result holds.

        .DESCRIPTION
            Collects garbage first, so the memory before is what is live; runs the script block
            with a stopwatch; reads the memory again while the result is still held, so the
            difference is what the reader returned and kept. Writes a MEASURE line to the
            information stream.

        .PARAMETER Name
            The name of the measurement, for the MEASURE line.

        .PARAMETER Lines
            How many log lines the reader was given, for the MEASURE line.

        .PARAMETER Reader
            The call to measure.

        .EXAMPLE
            Measure-Reader -Name 'Get-IntuneAgentLog' -Lines 2500 -Reader { Get-IntuneAgentLog -Path $folder }

            Returns the count, seconds and megabytes of one run of the log reader.

        .INPUTS
            None.

        .OUTPUTS
            IntuneScriptLab.Test.Measurement. Count, Seconds and Megabytes.
        #>
        [CmdletBinding()]
        [OutputType('IntuneScriptLab.Test.Measurement')]
        param(
            [Parameter(Mandatory)]
            [string]$Name,

            [Parameter(Mandatory)]
            [int]$Lines,

            [Parameter(Mandatory)]
            [scriptblock]$Reader
        )

        [System.GC]::Collect()
        $memoryBefore = [System.GC]::GetTotalMemory($true)
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $result = @(& $Reader)
        $stopwatch.Stop()
        $memoryAfter = [System.GC]::GetTotalMemory($false)
        $measurement = [pscustomobject]@{
            PSTypeName = 'IntuneScriptLab.Test.Measurement'
            Count = $result.Count
            Seconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
            Megabytes = [math]::Round(($memoryAfter - $memoryBefore) / 1MB, 1)
        }
        $line = 'MEASURE {0} lines={1} seconds={2} megabytes={3} powershell={4}' -f $Name, $Lines,
        $measurement.Seconds, $measurement.Megabytes, $PSVersionTable.PSVersion
        Write-Information -MessageData $line -InformationAction Continue
        $measurement
    }

    $script:SmallRuns = 500
    $script:LargeRuns = 2000
    $script:SmallLogs = New-HealthScriptsLog -Runs $script:SmallRuns
    $script:LargeLogs = New-HealthScriptsLog -Runs $script:LargeRuns
}

Describe 'Agent log readers on a large log' -Tag 'Performance' {

    Context 'Get-IntuneAgentLog' {
        BeforeAll {
            $script:LogSmall = Measure-Reader -Name 'Get-IntuneAgentLog' -Lines ($script:SmallRuns * 5) -Reader {
                Get-IntuneAgentLog -Path $script:SmallLogs
            }
            $script:LogLarge = Measure-Reader -Name 'Get-IntuneAgentLog' -Lines ($script:LargeRuns * 5) -Reader {
                Get-IntuneAgentLog -Path $script:LargeLogs
            }
        }

        It 'returns one entry for each of the 10,000 lines' {
            $script:LogLarge.Count | Should-Be ($script:LargeRuns * 5)
        }

        It 'reads 10,000 lines in less than 30 seconds' {
            $script:LogLarge.Seconds | Should-BeLessThan 30
        }

        It 'holds less than 300 MB for the entries of 10,000 lines' {
            $script:LogLarge.Megabytes | Should-BeLessThan 300
        }

        It 'takes less than six times as long for four times the lines' {
            # The smaller log's time is at least a tenth of a second, so that the ratio is not
            # taken against the resolution of the clock
            $base = [math]::Max($script:LogSmall.Seconds, 0.1)
            $script:LogLarge.Seconds / $base | Should-BeLessThan 6
        }
    }

    Context 'Get-IntuneAgentTimeline' {
        BeforeAll {
            $timelineSmall = @{ Name = 'Get-IntuneAgentTimeline'; Lines = $script:SmallRuns * 5 }
            $script:TimelineSmall = Measure-Reader @timelineSmall -Reader {
                Get-IntuneAgentTimeline -Path $script:SmallLogs
            }
            $timelineLarge = @{ Name = 'Get-IntuneAgentTimeline'; Lines = $script:LargeRuns * 5 }
            $script:TimelineLarge = Measure-Reader @timelineLarge -Reader {
                Get-IntuneAgentTimeline -Path $script:LargeLogs
            }
        }

        It 'returns one timeline for each of the 2,000 policies' {
            $script:TimelineLarge.Count | Should-Be $script:LargeRuns
        }

        It 'builds the timelines of 10,000 lines in less than 45 seconds' {
            $script:TimelineLarge.Seconds | Should-BeLessThan 45
        }

        It 'holds less than 300 MB for the timelines of 10,000 lines' {
            $script:TimelineLarge.Megabytes | Should-BeLessThan 300
        }

        It 'takes less than six times as long for four times the lines' {
            $base = [math]::Max($script:TimelineSmall.Seconds, 0.1)
            $script:TimelineLarge.Seconds / $base | Should-BeLessThan 6
        }
    }
}
