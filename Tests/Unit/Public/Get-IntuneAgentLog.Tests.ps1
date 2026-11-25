#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Reading a log folder the way the agent leaves it: four logs plus a rolled one and a stranger,
    merged in time order, classified, and filtered by log, id, event, level, time and pattern.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')

    function script:New-CmTraceLine {
        <#
        .SYNOPSIS
            Builds the text of one log entry in the CMTrace format.

        .DESCRIPTION
            Returns one line with the message, time, date, component, type and thread in the places
            the log readers find them, so that the suite writes log files without spelling out the
            format each time. The defaults are those of an IntuneManagementExtension entry.

        .PARAMETER Message
            The text of the entry.

        .PARAMETER Time
            The time field, as the log writes it.

        .PARAMETER Date
            The date field, month-day-year.

        .PARAMETER Type
            The type field of the entry, 1 by default.

        .PARAMETER Component
            The component that wrote the entry, IntuneManagementExtension by default.

        .PARAMETER Thread
            The thread field of the entry, 4 by default.

        .EXAMPLE
            New-CmTraceLine -Message 'Sensor heartbeat' -Time '08:00:00.0000000' -Component 'Sensor' -Type 3

            Returns a Sensor entry of type 3 dated 9-25-2026.

        .INPUTS
            None.

        .OUTPUTS
            System.String. The line, without a line ending.
        #>
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [string]$Message,

            [string]$Time,

            [string]$Date = '9-25-2026',

            [int]$Type = 1,

            [string]$Component = 'IntuneManagementExtension',

            [int]$Thread = 4
        )

        "<![LOG[$Message]LOG]!><time=`"$Time`" date=`"$Date`" component=`"$Component`" context=`"`" " +
        "type=`"$Type`" thread=`"$Thread`" file=`"`">"
    }
    function script:Write-TestLog {
        <#
        .SYNOPSIS
            Writes the lines of a log file into a folder and returns the file's path.

        .DESCRIPTION
            Creates the folder when it is missing, ends every line with CRLF, and writes the file as
            UTF-8 without a byte order mark.

        .PARAMETER Folder
            The folder that holds the log file.

        .PARAMETER Name
            The file name of the log.

        .PARAMETER Lines
            The lines of the log, as New-CmTraceLine returns them.

        .EXAMPLE
            Write-TestLog $script:Logs 'Sensor.log' @(New-CmTraceLine -Message 'x' -Time '08:00:00.0000000')

            Writes Sensor.log with one entry and returns its path.

        .INPUTS
            None.

        .OUTPUTS
            System.String. The full path of the log file.
        #>
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [string]$Folder,

            [string]$Name,

            [string[]]$Lines
        )

        $null = New-Item -ItemType Directory -Path $Folder -Force
        $path = Join-Path $Folder $Name
        $content = ($Lines -join "`r`n") + "`r`n"
        [System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))
        $path
    }
    $script:Policy = 'bbf7e139-fe9d-4783-80df-627b8e084059'
    $script:App = '9b6543c3-6d66-4cfb-a8fb-d780079278f6'
    $script:Logs = Join-Path $TestDrive 'Logs'
    $script:Executor = @{ Component = 'AgentExecutor'; Thread = 1 }
    $inspect = "[HS] inspect hourly schedule for policy $($script:Policy): UTC = False, Interval = 1, Time = "
    $verdict = "[HS] the pre-remdiation detection script compliance result for $($script:Policy) is False"
    $detected = "[Win32App][DetectionActionHandler] Detection for policy with id: $($script:App) " +
    'resulted in action status: Success and detection state: NotDetected.'
    Write-TestLog $script:Logs 'IntuneManagementExtension-20260924-131114.log' @(
        New-CmTraceLine -Message '[PowerShell] Get 25 policies' -Time '12:38:00.0000000' -Date '9-24-2026'
    )
    Write-TestLog $script:Logs 'IntuneManagementExtension.log' @(
        New-CmTraceLine -Message '[PowerShell] Get 26 policies' -Time '08:40:10.0000000'
        New-CmTraceLine -Message 'Launch powershell executor in machine session' -Time '08:45:19.0000000'
        New-CmTraceLine -Message 'Powershell execution is done, exitCode = 1' -Time '08:45:26.0000000' -Type 2
    )
    Write-TestLog $script:Logs 'HealthScripts.log' @(
        New-CmTraceLine -Message $inspect -Time '08:40:13.0000000' -Component 'HealthScripts'
        $cmTraceLineSplat = @{
            Message = "[HS] Runner: script $($script:Policy) will try to execute now."
            Time = '08:45:14.0000000'
            Component = 'HealthScripts'
        }
        New-CmTraceLine @cmTraceLineSplat
        New-CmTraceLine -Message $verdict -Time '08:45:26.5000000' -Component 'HealthScripts'
    )
    Write-TestLog $script:Logs 'AppWorkload.log' @(
        New-CmTraceLine -Message $detected -Time '08:38:04.0000000' -Component 'AppWorkload'
        New-CmTraceLine -Message '[Win32App] lpExitCode 0' -Time '08:38:40.0000000' -Component 'AppWorkload'
    )
    Write-TestLog $script:Logs 'AgentExecutor.log' @(
        New-CmTraceLine -Message 'Powershell exit code is 1' -Time '08:45:25.0000000' @script:Executor
    )
    Write-TestLog $script:Logs 'Sensor.log' @(
        New-CmTraceLine -Message 'Sensor heartbeat' -Time '08:00:00.0000000' -Component 'Sensor' -Type 3
    )
}

Describe 'Get-IntuneAgentLog' -Tag 'Unit', 'Public' {

    Context 'Parameter Validation' {
        It 'limits -Log and -Level to the known values and -Last to a positive count' {
            $command = Get-Command Get-IntuneAgentLog
            $command.Parameters['Log'].Attributes.ValidValues |
                Should-BeCollection @('Agent', 'AppWorkload', 'HealthScripts', 'AgentExecutor', 'All')
            $command.Parameters['Level'].Attributes.ValidValues |
                Should-BeCollection @('Information', 'Warning', 'Error')
            { Get-IntuneAgentLog -Path $script:Logs -Last 0 } | Should-Throw
        }

        It 'rejects an event name that is not in the table, naming the way to list them' {
            { Get-IntuneAgentLog -Path $script:Logs -EventName Nope } |
                Should-Throw -ExceptionMessage "*Unknown event 'Nope'*-ListEvent*"
            { Get-IntuneAgentLog -Path $script:Logs -EventName Nope } |
                Should-Throw -FullyQualifiedErrorId 'UnknownAgentLogEvent,Get-IntuneAgentLog'
        }

        It 'reports a path that does not exist and warns for a folder with no logs' {
            $nowhere = Join-Path $TestDrive 'nowhere'
            $warnings = @()
            $logSplat = @{ Path = $nowhere; ErrorAction = 'Continue'; WarningVariable = 'warnings' }
            $output = Get-IntuneAgentLog @logSplat 2>&1 3>$null
            $errors = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $errors | Should-BeCollection -Count 1
            $errors[0].FullyQualifiedErrorId | Should-BeLikeString 'PathNotFound,*'
            @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }).Count | Should-Be 0
            # The error has said why there is nothing; the warning about no logs would say it again
            $warnings.Count | Should-Be 0
            $emptyFolder = Join-Path $TestDrive 'empty'
            $null = New-Item -ItemType Directory -Path $emptyFolder -Force
            $warnings = @()
            $result = @(Get-IntuneAgentLog -Path $emptyFolder -WarningVariable warnings 3>$null)
            $result.Count | Should-Be 0
            $warnings -join ' ' | Should-BeLikeString '*No log files under*'
        }
    }

    Context 'Core Functionality' {
        It 'merges the four agent logs, rolled files included, in time order and classifies each entry' {
            $entries = @(Get-IntuneAgentLog -Path $script:Logs)
            $entries.Count | Should-Be 10
            $entries[0].Message | Should-Be '[PowerShell] Get 25 policies'
            $entries[0].Log | Should-Be 'IntuneManagementExtension-20260924-131114'
            $entries[0].Event | Should-Be 'ScriptPolicyFetch'
            $entries[0].Detail | Should-Be '25'
            $entries[0].PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.AgentLogEntry'
            $entries.Log | Should-NotContainCollection 'Sensor'
            $times = $entries | ForEach-Object { $_.Time }
            $sorted = $times | Sort-Object
            @($times) | Should-BeCollection @($sorted)
            ($entries | Where-Object Event -eq 'RemediationStart').Id | Should-Be $script:Policy
            ($entries | Where-Object Event -eq 'DetectionResult').Detail | Should-Be 'pre False'
        }

        It 'reads only the selected logs, and every .log file with All' {
            $health = @(Get-IntuneAgentLog -Path $script:Logs -Log HealthScripts)
            $health.Count | Should-Be 3
            $health.Component | Should-All { $_ -eq 'HealthScripts' }
            $all = @(Get-IntuneAgentLog -Path $script:Logs -Log All)
            $all.Count | Should-Be 11
            $all.Log | Should-ContainCollection 'Sensor'
        }

        It 'reads a file given directly, whatever -Log says' {
            $entries = @(Get-IntuneAgentLog -Path (Join-Path $script:Logs 'Sensor.log') -Log HealthScripts)
            $entries.Count | Should-Be 1
            $entries[0].Level | Should-Be 'Error'
        }

        It 'filters by policy or app id across the logs' {
            $entries = @(Get-IntuneAgentLog -Path $script:Logs -Id $script:Policy)
            $entries.Count | Should-Be 3
            $entries.Log | Should-All { $_ -eq 'HealthScripts' }
            $both = @(Get-IntuneAgentLog -Path $script:Logs -Id $script:Policy, $script:App.ToUpper())
            $both.Count | Should-Be 4
        }

        It 'filters by event name, level, time window and pattern' {
            $events = @(Get-IntuneAgentLog -Path $script:Logs -EventName ScriptExit, ExecutorExit)
            $events.Event | Should-BeCollection @('ExecutorExit', 'ScriptExit')
            $events.Detail | Should-All { $_ -eq '1' }
            @(Get-IntuneAgentLog -Path $script:Logs -Level Warning).Message |
                Should-BeCollection @('Powershell execution is done, exitCode = 1')
            $window = @($intuneAgentLogSplat = @{
                    Path = $script:Logs
                    After = ([datetime]'2026-09-25 08:45:00')
                    Before = ([datetime]'2026-09-25 08:45:26')
                }
                Get-IntuneAgentLog @intuneAgentLogSplat)
            $window.Message | Should-BeCollection @(
                "[HS] Runner: script $($script:Policy) will try to execute now."
                'Launch powershell executor in machine session'
                'Powershell exit code is 1'
            )
            @(Get-IntuneAgentLog -Path $script:Logs -Pattern 'Get \d+ policies').Count | Should-Be 2
        }

        It 'does not read a rolled-over file whose last write is before -After' {
            # The rolled-over agent log in the fixture is written on 9-24; its entries cannot be after
            # the 25th, so the file is skipped on its timestamp alone
            $rolled = Join-Path $script:Logs 'IntuneManagementExtension-20260924-131114.log'
            (Get-Item $rolled).LastWriteTime = [datetime]'2026-09-24 13:11:14'
            Mock ConvertFrom-IslCmTraceLog -ModuleName IntuneScriptLab { @() }
            $null = Get-IntuneAgentLog -Path $script:Logs -Log Agent -After ([datetime]'2026-09-25')
            $invokeSplat = @{ ModuleName = 'IntuneScriptLab'; Exactly = $true; Times = 1 }
            Should-Invoke ConvertFrom-IslCmTraceLog @invokeSplat -ParameterFilter {
                $Path -like '*\IntuneManagementExtension.log'
            }
        }

        It 'keeps the most recent entries with -Last, after the other filters' {
            $last = @(Get-IntuneAgentLog -Path $script:Logs -Last 2)
            $last.Message | Should-BeCollection @(
                'Powershell execution is done, exitCode = 1'
                "[HS] the pre-remdiation detection script compliance result for $($script:Policy) is False"
            )
            @(Get-IntuneAgentLog -Path $script:Logs -Log AppWorkload -Last 5).Count | Should-Be 2
        }

        It 'lists the event table with -ListEvent' {
            $definitions = @(Get-IntuneAgentLog -ListEvent)
            $definitions.Count | Should-BeGreaterThan 25
            $definitions[0].PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.AgentLogEventDefinition'
            ($definitions | Where-Object Event -eq 'ScriptExit').Pattern | Should-BeLikeString '*exitCode*'
        }

        It 'defaults to the agent log folder under ProgramData' {
            $programData = $env:ProgramData
            try {
                $env:ProgramData = $TestDrive
                $folder = Join-Path $TestDrive 'Microsoft\IntuneManagementExtension\Logs'
                $null = Write-TestLog $folder 'AgentExecutor.log' @(
                    New-CmTraceLine -Message 'Powershell exit code is 0' -Time '10:00:00.0000000' @script:Executor
                )
                $entries = @(Get-IntuneAgentLog)
                $entries.Count | Should-Be 1
                $entries[0].Event | Should-Be 'ExecutorExit'
            } finally {
                $env:ProgramData = $programData
            }
        }
    }

    Context 'Error Handling' {
        BeforeAll {
            # The logs of the fixture without its AgentExecutor.log, and in its place one whose
            # second entry has no time
            $script:Mixed = Join-Path $TestDrive 'MixedLogs'
            Copy-Item -LiteralPath $script:Logs -Destination $script:Mixed -Recurse
            $null = Write-TestLog $script:Mixed 'AgentExecutor.log' @(
                New-CmTraceLine -Time '08:40:13.0000000' -Message 'a good entry'
                New-CmTraceLine -Time 'noon' -Message 'an entry whose time is not one'
            )
            $script:Others = 'Agent', 'AppWorkload', 'HealthScripts'
            $script:Readable = @(Get-IntuneAgentLog -Path $script:Logs -Log $script:Others).Count
        }

        It 'leaves one record in a caller''s -ErrorVariable for a path that does not exist' {
            $missing = Join-Path $TestDrive 'no-such-logs'

            $null = Get-IntuneAgentLog -Path $missing -ErrorVariable collected -ErrorAction SilentlyContinue

            @($collected) | Should-BeCollection -Count 1
            $collected[0].FullyQualifiedErrorId | Should-BeLikeString 'PathNotFound,Get-IntuneAgentLog'
        }

        It 'reports a log it cannot parse and still returns the entries of the others' {
            $script:Readable | Should-BeGreaterThan 0
            $output = Get-IntuneAgentLog -Path $script:Mixed -ErrorAction Continue 2>&1
            $errors = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $entries = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })

            $errors | Should-BeCollection -Count 1
            $errors[0].FullyQualifiedErrorId | Should-BeLikeString 'CmTraceTimestampInvalid,*'
            $entries.Count | Should-Be $script:Readable
            # The log that failed gives nothing, not the entries before the one that broke it
            @($entries | Where-Object Log -eq 'AgentExecutor').Count | Should-Be 0
        }

        It 'reports a path that does not exist and still reads the other paths' {
            $paths = (Join-Path $TestDrive 'nowhere'), $script:Logs
            $output = Get-IntuneAgentLog -Path $paths -Log $script:Others -ErrorAction Continue 2>&1
            $errors = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })

            $errors | Should-BeCollection -Count 1
            $errors[0].FullyQualifiedErrorId | Should-BeLikeString 'PathNotFound,*'
            @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }).Count |
                Should-Be $script:Readable
        }

        It 'ends at the first such error when the caller asks it to stop' {
            { Get-IntuneAgentLog -Path $script:Mixed -ErrorAction Stop } |
                Should-Throw -FullyQualifiedErrorId 'CmTraceTimestampInvalid,*'
            { Get-IntuneAgentLog -Path (Join-Path $TestDrive 'nowhere') -ErrorAction Stop } |
                Should-Throw -FullyQualifiedErrorId 'PathNotFound,*'
        }

        It 'ends on a bad argument and reports a bad log, for a script without try' {
            # Should-Throw cannot show what such a caller sees: it calls inside a try, where every
            # error travels all the way up. The script here has none
            $logs = $script:Logs
            $mixed = $script:Mixed
            $run = Invoke-CallerScript -Statement @(
                "`$unknown = @(Get-IntuneAgentLog -Path '$logs' -EventName Nope)"
                "'unknown: ' + `$unknown.Count"
                "`$mixed = @(Get-IntuneAgentLog -Path '$mixed')"
                "'mixed: ' + `$mixed.Count"
            )

            $run.ReachedEnd | Should-BeTrue
            $run.Output | Should-BeCollection -Count 2
            $run.Output[0] | Should-Be 'unknown: 0'
            $run.Output[1] | Should-Be "mixed: $($script:Readable)"
            # One error for each failure, and none from a statement that ran after one
            $run.ErrorId | Should-BeCollection -Count 2
            $run.ErrorId[0] | Should-Be 'UnknownAgentLogEvent,Get-IntuneAgentLog'
            $run.ErrorId[1] | Should-BeLikeString 'CmTraceTimestampInvalid,*'
        }
    }
}
