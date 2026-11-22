#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
.SYNOPSIS
Runs the Pester suites of this repository in shuffled order and fails when they do not pass.

.DESCRIPTION
The one way the suites are run, on a developer's computer and in every CI job, so that both get
the same answer. The run is shuffled, and the seed is printed and is part of the failure
message, so that an order which fails can be run again. The script fails when Pester's result
is not Passed, which also covers a failed BeforeAll or AfterAll and a file that failed
discovery, when no tests ran, and, with -CodeCoverage, when coverage of Public and Private is
below -MinimumCoverage.

Suites that need an elevated session, a lab account or PSScriptAnalyzer skip themselves, so the
script needs neither elevation nor a tenant. It runs on PowerShell 7 and on Windows PowerShell
5.1.

.PARAMETER TestType
Which suites to run. Unit is Tests/Unit and Validation/Tests/Unit. Integration is
Tests/Integration, the suites that start real Windows PowerShell processes. All, the default,
is both.

.PARAMETER ExcludeTag
Tags of tests to leave out, for example Elevated for the tests that run as SYSTEM. Those tests
skip themselves in a session that is not elevated; the tag leaves them out of an elevated one.

.PARAMETER CodeCoverage
Measures the coverage of Public, Private and Private/Rules, and fails below -MinimumCoverage.

.PARAMETER MinimumCoverage
The lowest acceptable coverage, as a percentage of commands. The default is 80.

.PARAMETER ShuffleSeed
The seed of the shuffled order. The default, 0, takes a new seed for each run. Pass the seed
from a failure message to run that order again.

.PARAMETER OutputPath
A folder for the reports: testResults.xml in NUnit format and, with -CodeCoverage,
coverage.xml in JaCoCo format. Left out, no report is written.

.PARAMETER Output
The detail Pester prints: None, Normal, Detailed or Diagnostic. The default is Normal.

.PARAMETER SummaryPath
A Markdown file to which a summary of the run is appended: the counts, the shuffle seed and,
with -CodeCoverage, the coverage. It is written before the checks, so a failed run has one
too. CI passes the file that GITHUB_STEP_SUMMARY names.

.PARAMETER PassThru
Returns the Pester result object after the checks have passed.

.EXAMPLE
./Tests/Invoke-Tests.ps1

Runs every suite in a new shuffled order.

.EXAMPLE
./Tests/Invoke-Tests.ps1 -TestType Unit -ShuffleSeed 1741705376

Runs the unit suites in the order that seed gives, to repeat a failure.

.EXAMPLE
./Tests/Invoke-Tests.ps1 -ExcludeTag Elevated

Runs every suite except the tests that run as SYSTEM.

.EXAMPLE
./Tests/Invoke-Tests.ps1 -CodeCoverage -OutputPath ./out/reports -Output Detailed

Runs every suite with the coverage gate and writes both reports, as the tests job of CI does.

.INPUTS
None.

.OUTPUTS
None, or with -PassThru the Pester.Run object of the run.
#>
[CmdletBinding()]
[OutputType([object])]
param(
    [Parameter()]
    [ValidateSet('Unit', 'Integration', 'All')]
    [string]$TestType = 'All',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$ExcludeTag,

    [Parameter()]
    [switch]$CodeCoverage,

    [Parameter()]
    [ValidateRange(0, 100)]
    [int]$MinimumCoverage = 80,

    [Parameter()]
    [ValidateRange(0, 2147483647)]
    [int]$ShuffleSeed = 0,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath,

    [Parameter()]
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$Output = 'Normal',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SummaryPath,

    [Parameter()]
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$validationRoot = Join-Path -Path $repositoryRoot -ChildPath 'Validation'
$validationTests = Join-Path -Path $validationRoot -ChildPath 'Tests'
$suites = @{
    Unit = @(
        (Join-Path -Path $PSScriptRoot -ChildPath 'Unit')
        (Join-Path -Path $validationTests -ChildPath 'Unit')
    )
    Integration = @(
        (Join-Path -Path $PSScriptRoot -ChildPath 'Integration')
    )
}
$testPaths = if ($TestType -eq 'All') { $suites['Unit'] + $suites['Integration'] } else { $suites[$TestType] }

$configuration = New-PesterConfiguration
$configuration.Run.Path = $testPaths
$configuration.Run.PassThru = $true
$configuration.Run.Shuffle = $true
$configuration.Run.ShuffleSeed = $ShuffleSeed
$configuration.Output.Verbosity = $Output
# Every test file uses the Pester 6 assertions, so the Pester 5 form can stay off
$configuration.Should.DisableV5 = $true
if ($ExcludeTag) {
    $configuration.Filter.ExcludeTag = $ExcludeTag
}

$reportFolder = $null
if ($OutputPath) {
    $reportFolder = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($OutputPath)
    $null = New-Item -Path $reportFolder -ItemType Directory -Force
    $configuration.TestResult.Enabled = $true
    $configuration.TestResult.OutputPath = Join-Path -Path $reportFolder -ChildPath 'testResults.xml'
}

if ($CodeCoverage) {
    $privateFolder = Join-Path -Path $repositoryRoot -ChildPath 'Private'
    $coverageFolders = @(
        (Join-Path -Path $repositoryRoot -ChildPath 'Public')
        $privateFolder
        (Join-Path -Path $privateFolder -ChildPath 'Rules')
    )
    # Every entry must exist: Pester reports 0 percent, and still passes, for a path that matches
    # nothing
    $coveragePaths = foreach ($coverageFolder in $coverageFolders) {
        if (-not (Test-Path -LiteralPath $coverageFolder -PathType Container)) {
            throw "The coverage folder '$coverageFolder' does not exist."
        }
        Join-Path -Path $coverageFolder -ChildPath '*.ps1'
    }
    $configuration.CodeCoverage.Enabled = $true
    $configuration.CodeCoverage.Path = $coveragePaths
    # CoveragePercentTarget only sets the figure Pester reports against; the check below enforces it
    $configuration.CodeCoverage.CoveragePercentTarget = $MinimumCoverage
    if ($null -ne $reportFolder) {
        $configuration.CodeCoverage.OutputPath = Join-Path -Path $reportFolder -ChildPath 'coverage.xml'
    } else {
        $coverageFile = "IntuneScriptLab-coverage-$([guid]::NewGuid().ToString('N')).xml"
        $temporaryFolder = [System.IO.Path]::GetTempPath()
        $configuration.CodeCoverage.OutputPath = Join-Path -Path $temporaryFolder -ChildPath $coverageFile
    }
}

# Pester runs the test files in scopes below this one, so they would inherit this script's strict
# mode, and when the script is started with -File this scope is the global one, which the
# module's functions see as well. The suites, the validation kit and the module are not yet
# written for strict mode (#63, #70, #71), so it is off for the run and on again after it.
Set-StrictMode -Off
try {
    $result = Invoke-Pester -Configuration $configuration
} finally {
    Set-StrictMode -Version Latest
}

if ($null -eq $result -or $result.TotalCount -eq 0) {
    throw "Pester ran no tests for '$TestType'."
}

$seed = $result.Configuration.Run.ShuffleSeed.Value
$counts = "passed $($result.PassedCount), failed $($result.FailedCount), skipped $($result.SkippedCount)"
$summary = "Pester: $counts. Shuffle seed $seed."
$coverage = $null
if ($CodeCoverage) {
    $coverage = [math]::Round($result.CodeCoverage.CoveragePercent, 2)
    $summary = "$summary Code coverage $coverage percent."
}
Write-Information -InformationAction Continue -MessageData $summary

if ($SummaryPath) {
    # Written before the checks below, so that a run which fails them still leaves its summary
    $summaryFile = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($SummaryPath)
    $architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    $heading = "## Pester, $TestType tests, PowerShell $($PSVersionTable.PSVersion) on $architecture"
    $markdown = "$heading`n`n$summary`n`n"
    [System.IO.File]::AppendAllText($summaryFile, $markdown, [System.Text.UTF8Encoding]::new($false))
}

if ($result.Result -ne 'Passed') {
    $failures = "Failed tests: $($result.FailedCount). Failed blocks: $($result.FailedBlocksCount)."
    $failures = "$failures Failed files: $($result.FailedContainersCount)."
    throw "Pester result is '$($result.Result)'. $failures Run the same order with -ShuffleSeed $seed."
}

if ($CodeCoverage -and $coverage -lt $MinimumCoverage) {
    $missedByFile = @($result.CodeCoverage.CommandsMissed |
            Group-Object -Property File |
            Sort-Object -Property Name)
    foreach ($file in $missedByFile) {
        $line = "  $($file.Name): $($file.Count) uncovered command(s)"
        Write-Information -InformationAction Continue -MessageData $line
    }
    throw "Code coverage is $coverage percent. The minimum is $MinimumCoverage."
}

if ($PassThru) {
    $result
}
