#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The CMTrace parser and its timestamp conversion, against lines in the exact shape the Intune
    Management Extension writes (raw tails from a test device), including a message that spans
    lines and a file another process holds open for writing.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force

    function script:New-CmTraceLine {
        param([string]$Message, [string]$Time, [string]$Date = '9-25-2026', [int]$Type = 1,
            [string]$Component = 'HealthScripts', [int]$Thread = 71)
        "<![LOG[$Message]LOG]!><time=`"$Time`" date=`"$Date`" component=`"$Component`" context=`"`" " +
        "type=`"$Type`" thread=`"$Thread`" file=`"`">"
    }
    $script:LogPath = Join-Path $TestDrive 'HealthScripts.log'
    $runner = '[HS] Runner: script bbf7e139-fe9d-4783-80df-627b8e084059 will try to execute now.'
    $lines = @(
        New-CmTraceLine -Message $runner -Time '08:45:14.1234567'
        $cmTraceLineSplat = @{
            Message   = "error from script =At C:\detect.ps1:60 char:35`r`n+ throw 'x'`r`n+ ~~~"
            Time      = '08:45:19.5000000'
            Type      = 3
            Component = 'AgentExecutor'
            Thread    = 1
        }
        New-CmTraceLine @cmTraceLineSplat
        $cmTraceLineSplat2 = @{
            Message = '[HS] the pre-remdiation detection script compliance result is False'
            Time    = '08:45:26.987+000'
            Type    = 2
        }
        New-CmTraceLine @cmTraceLineSplat2
    )
    $content = ($lines -join "`r`n") + "`r`n"
    [System.IO.File]::WriteAllText($script:LogPath, $content, [System.Text.UTF8Encoding]::new($false))
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertFrom-IslCmTraceLog' -Tag 'Unit', 'Private' {

    It 'returns one typed entry per CMTrace record, in file order' {
        $entries = @(InModuleScope IntuneScriptLab -Parameters @{ Path = $script:LogPath } {
                ConvertFrom-IslCmTraceLog -Path $Path
            })
        $entries.Count | Should-Be 3
        $entries[0].PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.AgentLogEntry'
        $entries[0].Message | Should-BeLikeString '[[]HS] Runner: script bbf7e139-*will try to execute now.'
        $entries[0].Component | Should-Be 'HealthScripts'
        $entries[0].Thread | Should-Be 71
        $entries[0].Log | Should-Be 'HealthScripts'
        $entries[0].Event | Should-BeNull
    }

    It 'maps type 1, 2 and 3 to Information, Warning and Error' {
        $entries = @(InModuleScope IntuneScriptLab -Parameters @{ Path = $script:LogPath } {
                ConvertFrom-IslCmTraceLog -Path $Path
            })
        $entries.Level | Should-BeCollection @('Information', 'Error', 'Warning')
    }

    It 'keeps a multi-line message whole and numbers the lines the entries start on' {
        $entries = @(InModuleScope IntuneScriptLab -Parameters @{ Path = $script:LogPath } {
                ConvertFrom-IslCmTraceLog -Path $Path
            })
        $entries[1].Message | Should-BeLikeString "error from script =At C:\detect.ps1:60 char:35*+ ~~~"
        $entries[1].Message.Split("`n").Count | Should-Be 3
        $entries.Line | Should-BeCollection @(1, 2, 5)
    }

    It 'converts the time and date attributes, with and without a UTC bias suffix' {
        $entries = @(InModuleScope IntuneScriptLab -Parameters @{ Path = $script:LogPath } {
                ConvertFrom-IslCmTraceLog -Path $Path
            })
        $entries[0].Time | Should-Be ([datetime]::new(2026, 9, 25, 8, 45, 14).AddTicks(1234567))
        $entries[2].Time | Should-Be ([datetime]::new(2026, 9, 25, 8, 45, 26, 987))
    }

    It 'reads a log the agent still holds open for writing, where ReadAllText cannot' {
        $writer = [System.IO.File]::Open($script:LogPath, [System.IO.FileMode]::Append,
            [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
        try {
            { [System.IO.File]::ReadAllText($script:LogPath) } | Should-Throw
            $entries = @(InModuleScope IntuneScriptLab -Parameters @{ Path = $script:LogPath } {
                    ConvertFrom-IslCmTraceLog -Path $Path
                })
            $entries.Count | Should-Be 3
        }
        finally {
            $writer.Dispose()
        }
    }

    It 'returns nothing for an empty file and fails for a missing one' {
        $empty = Join-Path $TestDrive 'empty.log'
        [System.IO.File]::WriteAllText($empty, '')
        $entries = @(InModuleScope IntuneScriptLab -Parameters @{ Path = $empty } {
                ConvertFrom-IslCmTraceLog -Path $Path
            })
        $entries.Count | Should-Be 0
        { InModuleScope IntuneScriptLab { ConvertFrom-IslCmTraceLog -Path 'C:\nowhere\none.log' } } | Should-Throw
    }
}

Describe 'ConvertTo-IslCmTraceTime' -Tag 'Unit', 'Private' {

    It 'parses <Time> on <Date> as <Expected>' -ForEach @(
        @{
            Time = '09:06:34.5901742'; Date = '9-25-2026'
            Expected = [datetime]::new(2026, 9, 25, 9, 6, 34).AddTicks(5901742)
        }
        @{ Time = '12:38:05.123+000'; Date = '12-1-2026'; Expected = [datetime]::new(2026, 12, 1, 12, 38, 5, 123) }
        @{ Time = '23:59:59.5-420'; Date = '1-9-2027'; Expected = [datetime]::new(2027, 1, 9, 23, 59, 59, 500) }
        @{ Time = '00:00:00'; Date = '2-28-2026'; Expected = [datetime]::new(2026, 2, 28, 0, 0, 0) }
    ) {
        $result = InModuleScope IntuneScriptLab -Parameters @{ Time = $Time; Date = $Date } {
            ConvertTo-IslCmTraceTime -Time $Time -Date $Date
        }
        $result | Should-Be $Expected
    }

    It 'rejects a value that is not a CMTrace timestamp' {
        { InModuleScope IntuneScriptLab { ConvertTo-IslCmTraceTime -Time 'noon' -Date '9-25-2026' } } |
            Should-Throw -ExceptionMessage '*Not a CMTrace timestamp*'
        { InModuleScope IntuneScriptLab { ConvertTo-IslCmTraceTime -Time '09:00:00' -Date '2026-09-25' } } |
            Should-Throw
    }
}
