#Requires -Version 5.1

<#
.SYNOPSIS
    Compares the measurements of the performance tests with their recorded baselines.

.DESCRIPTION
    The performance gate of CIC-13. Tests/Performance writes one JSON line for each measurement
    to the file that ISL_PERFORMANCE_RESULTS names: the name of the reader, the lines of the log
    it read, the seconds it took and the megabytes its result kept. When the suite has run several
    times, the script takes the median of each measurement, so that one slow run does not decide,
    and compares it with the baseline recorded for the machine it runs on.

    Baselines are recorded for a runner: the image of a GitHub-hosted runner (the ImageOS variable
    it sets, such as win25), its architecture and the PowerShell version, as in win25/X64/7.6. A
    measurement fails when its median is more than the margin above its baseline: a margin of 0.5
    lets it be half as large again. A machine with no baseline, a developer's computer or a new
    runner image, is reported and not gated, so that a new image does not fail every build; its
    medians are printed in the form of a baseline entry, to be recorded with -Record.

.PARAMETER ResultPath
    The file of JSON lines that the performance tests wrote. The tests append to it, so delete it
    before a new recording; measurements from more than one PowerShell version are refused.

.PARAMETER BaselinePath
    The baselines. Default: Tests/Performance/Baselines.psd1.

.PARAMETER Runner
    The runner to compare with. Default: ImageOS/architecture/major.minor of PowerShell on a
    GitHub-hosted runner, and the computer's name elsewhere.

.PARAMETER Record
    Prints the medians as a baseline entry for the runner and compares nothing.

.EXAMPLE
    ./Build/Test-PerformanceBaseline.ps1 -ResultPath ./reports/performance/measurements.jsonl

    Compares the medians of the measurements with the baselines of this runner.

.EXAMPLE
    ./Build/Test-PerformanceBaseline.ps1 -ResultPath ./measurements.jsonl -Record

    Prints the medians as the baseline entry of this runner.

.INPUTS
    None.

.OUTPUTS
    None. A line for each measurement, as information records.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ResultPath,

    [Parameter()]
    [string]$BaselinePath,

    [Parameter()]
    [string]$Runner,

    [Parameter()]
    [switch]$Record
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1 has no $PSScriptRoot while it binds the parameters, so the defaults are set here
if (-not $BaselinePath) {
    $repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
    $testsFolder = Join-Path -Path $repositoryRoot -ChildPath 'Tests'
    $performanceFolder = Join-Path -Path $testsFolder -ChildPath 'Performance'
    $BaselinePath = Join-Path -Path $performanceFolder -ChildPath 'Baselines.psd1'
}
if (-not $Runner) {
    $version = '{0}.{1}' -f $PSVersionTable.PSVersion.Major, $PSVersionTable.PSVersion.Minor
    $architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    $machine = if ($env:ImageOS) { $env:ImageOS } else { $env:COMPUTERNAME }
    $Runner = '{0}/{1}/{2}' -f $machine, $architecture, $version
}

function Format-Invariant {
    <#
    .SYNOPSIS
        Formats a string with its numbers written as the invariant culture writes them.

    .DESCRIPTION
        The -f operator writes a number in the current culture, 1,06 in German, which a baseline
        entry pasted into Baselines.psd1 would then read as an array. This writes 1.06 whatever the
        culture.

    .PARAMETER Format
        The format string, as for -f.

    .PARAMETER Argument
        The values to put into it.

    .EXAMPLE
        Format-Invariant -Format '{0} s' -Argument 1.06

        Returns '1.06 s' in every culture.

    .INPUTS
        None.

    .OUTPUTS
        System.String. The formatted string.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Format,

        [Parameter(Mandatory)]
        [AllowNull()]
        [object[]]$Argument
    )

    [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, $Format, $Argument)
}


function Get-Median {
    <#
    .SYNOPSIS
        Gets the median of a set of numbers.

    .DESCRIPTION
        Sorts the numbers and returns the middle one, or the mean of the two in the middle when
        there is an even number of them.

    .PARAMETER Value
        The numbers.

    .EXAMPLE
        Get-Median -Value 3, 1, 2

        Returns 2.

    .INPUTS
        None.

    .OUTPUTS
        System.Double. The median.
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory)]
        [double[]]$Value
    )

    $sorted = @($Value | Sort-Object)
    $middle = [math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2 -eq 1) {
        $sorted[$middle]
    } else {
        ($sorted[$middle - 1] + $sorted[$middle]) / 2
    }
}


$lines = @([System.IO.File]::ReadAllLines((Resolve-Path -LiteralPath $ResultPath).ProviderPath) |
        Where-Object { $_.Trim() })
if ($lines.Count -eq 0) {
    throw "No measurements in '$ResultPath': the performance tests wrote nothing."
}
$results = @($lines | ForEach-Object { $_ | ConvertFrom-Json })
# One recording per file: medians over two PowerShell versions, or two versions of the code, would
# describe neither
$versions = @($results | ForEach-Object { $_.PSObject.Properties['PowerShell'] } | Where-Object { $_ } |
        ForEach-Object { "$($_.Value)" } | Sort-Object -Unique)
if ($versions.Count -gt 1) {
    throw ("The measurements in '$ResultPath' come from more than one PowerShell version " +
        "($($versions -join ', ')). Delete the file and record again.")
}
$medians = @(
    foreach ($group in @($results | Group-Object -Property Name, Lines | Sort-Object -Property Name)) {
        $first = $group.Group[0]
        [pscustomobject]@{
            Key = '{0}/{1}' -f $first.Name, $first.Lines
            Runs = $group.Count
            Seconds = [math]::Round((Get-Median -Value @($group.Group.Seconds)), 2)
            Megabytes = [math]::Round((Get-Median -Value @($group.Group.Megabytes)), 1)
        }
    }
)

if ($Record) {
    $entry = foreach ($median in $medians) {
        $values = $median.Key, $median.Seconds, $median.Megabytes
        Format-Invariant -Format "        '{0}' = @{{ Seconds = {1}; Megabytes = {2} }}" -Argument $values
    }
    Write-Information -InformationAction Continue -MessageData (
        "Baseline entry for '$Runner':`n    '$Runner' = @{`n$($entry -join "`n")`n    }")
    return
}

$baselines = Import-PowerShellDataFile -LiteralPath $BaselinePath
foreach ($key in 'Margin', 'Runners') {
    if (-not $baselines.ContainsKey($key)) {
        throw "The baselines '$BaselinePath' have no '$key' table."
    }
}
if (-not $baselines['Runners'].ContainsKey($Runner)) {
    $measured = ($medians | ForEach-Object {
            Format-Invariant -Format '{0} {1} s {2} MB' -Argument $_.Key, $_.Seconds, $_.Megabytes
        }) -join '; '
    Write-Warning ("No performance baseline for the runner '$Runner', so nothing is gated. Measured " +
        "(median of the runs): $measured. Record one with -Record.")
    return
}

$runnerBaselines = $baselines['Runners'][$Runner]
$failures = [System.Collections.Generic.List[string]]::new()
foreach ($median in $medians) {
    if (-not $runnerBaselines.ContainsKey($median.Key)) {
        Write-Information -InformationAction Continue -MessageData (
            "$($median.Key): $($median.Seconds) s, $($median.Megabytes) MB, no baseline")
        continue
    }
    $baseline = $runnerBaselines[$median.Key]
    foreach ($measure in 'Seconds', 'Megabytes') {
        $limit = [math]::Round($baseline[$measure] * (1 + $baselines['Margin'][$measure]), 2)
        $value = $median.$measure
        $verdict = if ($value -gt $limit) { 'over' } else { 'within' }
        $values = $median.Key, $value, $measure, $verdict, $limit, $baseline[$measure], $median.Runs
        $lineFormat = '{0}: {1} {2}, {3} the limit {4} (baseline {5}, median of {6} runs)'
        $line = Format-Invariant -Format $lineFormat -Argument $values
        Write-Information -MessageData $line -InformationAction Continue
        if ($verdict -eq 'over') {
            $failures.Add($line)
        }
    }
}
foreach ($baselineKey in $runnerBaselines.Keys) {
    if ($baselineKey -notin $medians.Key) {
        $failures.Add("$($baselineKey): has a baseline, and the performance tests measured nothing for it")
    }
}
if ($failures.Count -gt 0) {
    throw "The performance gate failed for '$Runner':`n$($failures -join "`n")"
}
Write-Information -InformationAction Continue -MessageData (
    "Performance gate: $($medians.Count) measurement(s) within the baselines of '$Runner'.")
