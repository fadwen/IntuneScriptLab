#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Build/Test-PerformanceBaseline.ps1, the performance gate (CIC-13), run against measurements
    and baselines written for each test: it must pass medians within the margin, fail one above
    it, take the median so that one slow run does not decide, and leave a runner without a
    baseline ungated. The script is called in this process, and what it writes is read from the
    information and warning streams.
#>

BeforeAll {
    $repositoryRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    $buildFolder = Join-Path -Path $repositoryRoot -ChildPath 'Build'
    $script:Gate = Join-Path -Path $buildFolder -ChildPath 'Test-PerformanceBaseline.ps1'

    function script:Invoke-Gate {
        <#
        .SYNOPSIS
            Runs the performance gate on measurements and baselines written for one test.

        .DESCRIPTION
            Writes the measurements as JSON lines and the baselines as a data file under TestDrive,
            runs Build/Test-PerformanceBaseline.ps1 on them for the runner 'test/X64/7.6', and
            returns what it wrote, the message of the error it ended with, if any, and whether it
            passed.

        .PARAMETER Measurement
            Hashtables of Name, Lines, Seconds and Megabytes, one for each measurement.

        .PARAMETER Baseline
            The text of the Runners table's entries for 'test/X64/7.6', or $null for no entry.

        .PARAMETER Record
            Runs the gate with -Record.

        .PARAMETER DefaultRunner
            Leaves -Runner out, so that the gate works out the runner itself.

        .PARAMETER Culture
            The culture the gate runs under, such as de-DE. Default: the current one.

        .EXAMPLE
            Invoke-Gate -Measurement @{ Name = 'R'; Lines = 10; Seconds = 1; Megabytes = 1 } -Baseline $null

            Runs the gate on one measurement for a runner with no baseline.

        .INPUTS
            None.

        .OUTPUTS
            IntuneScriptLab.Test.GateRun. Output, Failure and Passed.
        #>
        [CmdletBinding()]
        [OutputType('IntuneScriptLab.Test.GateRun')]
        param(
            [Parameter()]
            [hashtable[]]$Measurement = @(),

            [Parameter()]
            [AllowNull()]
            [string]$Baseline,

            [Parameter()]
            [switch]$Record,

            [Parameter()]
            [switch]$DefaultRunner,

            [Parameter()]
            [string]$Culture
        )

        $folder = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $folder
        $resultPath = Join-Path -Path $folder -ChildPath 'measurements.jsonl'
        $json = foreach ($item in $Measurement) { ([pscustomobject]$item | ConvertTo-Json -Compress) }
        [System.IO.File]::WriteAllText($resultPath, (@($json) -join "`n"), [System.Text.UTF8Encoding]::new($false))
        $runners = if ($Baseline) { "'test/X64/7.6' = @{ $Baseline }" } else { '' }
        $baselinePath = Join-Path -Path $folder -ChildPath 'Baselines.psd1'
        $data = "@{ Margin = @{ Seconds = 0.5; Megabytes = 0.5 }; Runners = @{ $runners } }"
        [System.IO.File]::WriteAllText($baselinePath, $data, [System.Text.UTF8Encoding]::new($false))

        $gateSplat = @{ ResultPath = $resultPath; BaselinePath = $baselinePath; Runner = 'test/X64/7.6' }
        if ($Record) {
            $gateSplat['Record'] = $true
        }
        if ($DefaultRunner) {
            $gateSplat.Remove('Runner')
        }
        $thread = [System.Threading.Thread]::CurrentThread
        $savedCulture = $thread.CurrentCulture
        $failure = $null
        $output = try {
            if ($Culture) {
                $thread.CurrentCulture = [System.Globalization.CultureInfo]::new($Culture)
            }
            & $script:Gate @gateSplat 6>&1 3>&1
        } catch {
            $failure = $_.Exception.Message
        } finally {
            $thread.CurrentCulture = $savedCulture
        }
        [pscustomobject]@{
            PSTypeName = 'IntuneScriptLab.Test.GateRun'
            Output = (@($output) | ForEach-Object { "$_" }) -join "`n"
            Failure = $failure
            Passed = $null -eq $failure
        }
    }

    $script:Reader = 'Get-IntuneAgentLog'
    $script:Base = "'Get-IntuneAgentLog/10000' = @{ Seconds = 4; Megabytes = 30 }"
}

Describe 'Build/Test-PerformanceBaseline.ps1' -Tag 'Unit', 'Build' {

    Context 'Measurements within the baselines' {
        It 'passes a median within the margin and says so for each measure' {
            $result = Invoke-Gate -Baseline $script:Base -Measurement @(
                @{ Name = $script:Reader; Lines = 10000; Seconds = 5.9; Megabytes = 44 }
            )

            $result.Passed | Should-BeTrue
            $result.Output | Should-BeLikeString '*Get-IntuneAgentLog/10000: 5.9 Seconds, within the limit 6 *'
            $result.Output | Should-BeLikeString '*44 Megabytes, within the limit 45 *'
            $result.Output | Should-BeLikeString '*1 measurement(s) within the baselines*'
        }

        It 'takes the median of the runs, so that one slow run does not fail the build' {
            $result = Invoke-Gate -Baseline $script:Base -Measurement @(
                @{ Name = $script:Reader; Lines = 10000; Seconds = 4.1; Megabytes = 30 }
                @{ Name = $script:Reader; Lines = 10000; Seconds = 20; Megabytes = 31 }
                @{ Name = $script:Reader; Lines = 10000; Seconds = 3.9; Megabytes = 29 }
            )

            $result.Passed | Should-BeTrue
            $result.Output | Should-BeLikeString '*4.1 Seconds, within the limit 6 (baseline 4, median of 3 runs)*'
        }
    }

    Context 'Measurements above the baselines' {
        It 'fails a median above the margin for <Measure>' -ForEach @(
            @{ Measure = 'Seconds'; Seconds = 6.1; Megabytes = 30 }
            @{ Measure = 'Megabytes'; Seconds = 4; Megabytes = 46 }
        ) {
            $result = Invoke-Gate -Baseline $script:Base -Measurement @(
                @{ Name = $script:Reader; Lines = 10000; Seconds = $Seconds; Megabytes = $Megabytes }
            )

            $result.Passed | Should-BeFalse
            $result.Failure | Should-BeLikeString "*Get-IntuneAgentLog/10000:* $Measure, over the limit*"
        }

        It 'fails when a measurement with a baseline was not taken' {
            $result = Invoke-Gate -Baseline $script:Base -Measurement @(
                @{ Name = 'Get-IntuneAgentTimeline'; Lines = 10000; Seconds = 1; Megabytes = 1 }
            )

            $result.Passed | Should-BeFalse
            $result.Failure | Should-BeLikeString '*Get-IntuneAgentLog/10000: has a baseline*measured nothing*'
        }

        It 'fails when the tests wrote no measurement' {
            $result = Invoke-Gate -Baseline $script:Base

            $result.Passed | Should-BeFalse
            $result.Failure | Should-BeLikeString '*No measurements*'
        }
    }

    Context 'What the gate reads' {
        It 'passes a size the baselines do not name, and says it has none' {
            $result = Invoke-Gate -Baseline $script:Base -Measurement @(
                @{ Name = $script:Reader; Lines = 10000; Seconds = 4; Megabytes = 30 }
                @{ Name = $script:Reader; Lines = 2500; Seconds = 1; Megabytes = 7 }
            )

            $result.Passed | Should-BeTrue
            $result.Output | Should-BeLikeString '*Get-IntuneAgentLog/2500: 1 s, 7 MB, no baseline*'
        }

        It 'refuses measurements from two PowerShell versions in one file' {
            $result = Invoke-Gate -Baseline $script:Base -Measurement @(
                @{ Name = $script:Reader; Lines = 10000; Seconds = 4; Megabytes = 30; PowerShell = '7.6.10' }
                @{ Name = $script:Reader; Lines = 10000; Seconds = 4; Megabytes = 30; PowerShell = '5.1.26100' }
            )

            $result.Passed | Should-BeFalse
            $result.Failure | Should-BeLikeString '*more than one PowerShell version (5.1.26100, 7.6.10)*'
        }

        It 'names the runner by the image, the architecture and the PowerShell version' {
            $savedImage = $env:ImageOS
            $env:ImageOS = 'win99'
            try {
                $result = Invoke-Gate -Baseline $script:Base -DefaultRunner -Measurement @(
                    @{ Name = $script:Reader; Lines = 10000; Seconds = 4; Megabytes = 30 }
                )
            } finally {
                $env:ImageOS = $savedImage
            }

            $architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
            $version = '{0}.{1}' -f $PSVersionTable.PSVersion.Major, $PSVersionTable.PSVersion.Minor
            $result.Output | Should-BeLikeString "*runner 'win99/$architecture/$version'*"
        }

        It 'writes numbers with a point under a culture that writes a comma' {
            $result = Invoke-Gate -Baseline $null -Record -Culture 'de-DE' -Measurement @(
                @{ Name = $script:Reader; Lines = 10000; Seconds = 1.06; Megabytes = 25.7 }
            )

            $entry = "'Get-IntuneAgentLog/10000' = @{ Seconds = 1.06; Megabytes = 25.7 }"
            $result.Output | Should-BeLikeString "*$entry*"
        }
    }
    Context 'A runner without baselines' {
        It 'warns, prints what it measured, and passes' {
            $result = Invoke-Gate -Baseline $null -Measurement @(
                @{ Name = $script:Reader; Lines = 10000; Seconds = 99; Megabytes = 999 }
            )

            $result.Passed | Should-BeTrue
            $result.Output | Should-BeLikeString "*No performance baseline for the runner 'test/X64/7.6'*"
            $result.Output | Should-BeLikeString '*Get-IntuneAgentLog/10000 99 s 999 MB*'
        }

        It 'prints the medians as a baseline entry with -Record' {
            $result = Invoke-Gate -Baseline $null -Record -Measurement @(
                @{ Name = $script:Reader; Lines = 10000; Seconds = 3; Megabytes = 20 }
                @{ Name = $script:Reader; Lines = 10000; Seconds = 5; Megabytes = 30 }
            )

            $result.Passed | Should-BeTrue
            $result.Output | Should-BeLikeString "*'test/X64/7.6' = @{*"
            $result.Output | Should-BeLikeString "*'Get-IntuneAgentLog/10000' = @{ Seconds = 4; Megabytes = 25 }*"
        }
    }
}
