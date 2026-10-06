#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Reading a log folder the way the agent leaves it: four logs plus a rolled one and a stranger,
    merged in time order, classified, and filtered by log, id, event, level, time and pattern.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force

    function script:New-CmTraceLine {
        param([string]$Message, [string]$Time, [string]$Date = '9-25-2026', [int]$Type = 1,
            [string]$Component = 'IntuneManagementExtension', [int]$Thread = 4)
        "<![LOG[$Message]LOG]!><time=`"$Time`" date=`"$Date`" component=`"$Component`" context=`"`" " +
        "type=`"$Type`" thread=`"$Thread`" file=`"`">"
    }
    function script:Write-TestLog {
        param([string]$Folder, [string]$Name, [string[]]$Lines)
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
            Message   = "[HS] Runner: script $($script:Policy) will try to execute now."
            Time      = '08:45:14.0000000'
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

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
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
        }

        It 'fails for a path that does not exist and warns for a folder with no logs' {
            { Get-IntuneAgentLog -Path (Join-Path $TestDrive 'nowhere') } | Should-Throw
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
                            Path   = $script:Logs
                            After  = ([datetime]'2026-09-25 08:45:00')
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
            }
            finally {
                $env:ProgramData = $programData
            }
        }
    }
}
