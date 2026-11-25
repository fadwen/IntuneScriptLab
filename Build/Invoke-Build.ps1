#Requires -Version 5.1

<#
.SYNOPSIS
    Rebuilds what the repository generates and runs every check, as CI would.

.DESCRIPTION
    The one local build command (PLT-12). In order, stopping at the first step that fails:

    1. Build/Build-Help.ps1 -SkipUpdate: the compiled help from the committed Markdown, the form
       the help job compares byte for byte.
    2. Build/Build-RuleReference.ps1: docs/Rules.md from the rules.
    3. Build/Test-MarkdownLink.ps1: the anchors and relative links of the Markdown.
    4. Build/Invoke-Analysis.ps1: PSScriptAnalyzer with the repository's settings, in a new
       process.
    5. Tests/Invoke-Tests.ps1 with -TestType in this host.
    6. Tests/Invoke-Tests.ps1 -TestType Unit under Windows PowerShell 5.1, on Windows, unless
       -SkipWindowsPowerShell.

    Steps 1 and 2 rewrite en-US/IntuneScriptLab-Help.xml and docs/Rules.md. When they change a
    file, git status shows it, and the change belongs in the same commit as its cause. The script
    ends with the list of files those two steps changed.

.PARAMETER TestType
    Which suites step 5 runs: Unit (the default), Integration or All.

.PARAMETER SkipTests
    Leaves out steps 5 and 6, for a change to documentation only.

.PARAMETER SkipWindowsPowerShell
    Leaves out step 6.

.EXAMPLE
    ./Build/Invoke-Build.ps1

    Rebuilds the help and the rule reference, checks the links, analyzes, and runs the unit suites
    in this host and under Windows PowerShell 5.1.

.EXAMPLE
    ./Build/Invoke-Build.ps1 -TestType All -SkipWindowsPowerShell

    The same with every suite in this host and none under Windows PowerShell 5.1.

.INPUTS
    None.

.OUTPUTS
    None. Each step's own output, then the generated files that changed, as information records.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('Unit', 'Integration', 'All')]
    [string]$TestType = 'Unit',

    [Parameter()]
    [switch]$SkipTests,

    [Parameter()]
    [switch]$SkipWindowsPowerShell
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$testsFolder = Join-Path -Path $repositoryRoot -ChildPath 'Tests'
$runner = Join-Path -Path $testsFolder -ChildPath 'Invoke-Tests.ps1'
$generated = 'en-US/IntuneScriptLab-Help.xml', 'docs/Rules.md'

function Write-BuildStep {
    <#
    .SYNOPSIS
        Writes the heading of one build step.

    .DESCRIPTION
        One line on the console before each step, so that a failure is read against the step
        that caused it.

    .PARAMETER Text
        The step's description.

    .EXAMPLE
        Write-BuildStep -Text 'Help'

        Writes '== Help'.

    .INPUTS
        None.

    .OUTPUTS
        None. The line is an information record.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    Write-Information -MessageData "== $Text" -InformationAction Continue
}


Write-BuildStep -Text 'Help: compiled from the committed Markdown'
& (Join-Path -Path $PSScriptRoot -ChildPath 'Build-Help.ps1') -SkipUpdate

Write-BuildStep -Text 'Rule reference: docs/Rules.md'
& (Join-Path -Path $PSScriptRoot -ChildPath 'Build-RuleReference.ps1')

Write-BuildStep -Text 'Markdown links'
& (Join-Path -Path $PSScriptRoot -ChildPath 'Test-MarkdownLink.ps1')

Write-BuildStep -Text 'PSScriptAnalyzer'
# A new process: once the help build has loaded the module, the analyzer resolves the module's
# Should-* aliases and reports every Pester assertion of the suites as an alias
$hostPath = (Get-Process -Id $PID).Path
$analysis = Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-Analysis.ps1'
& $hostPath -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $analysis
if ($LASTEXITCODE -ne 0) {
    throw "PSScriptAnalyzer reported findings (exit code $LASTEXITCODE)."
}

if (-not $SkipTests) {
    Write-BuildStep -Text "Tests ($TestType) in PowerShell $($PSVersionTable.PSVersion)"
    & $runner -TestType $TestType

    $onWindows = $PSVersionTable.PSVersion.Major -lt 6 -or $IsWindows
    $inDesktop = $PSVersionTable.PSEdition -eq 'Desktop'
    if ($onWindows -and -not $inDesktop -and -not $SkipWindowsPowerShell) {
        Write-BuildStep -Text 'Unit tests under Windows PowerShell 5.1'
        & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $runner -TestType Unit
        if ($LASTEXITCODE -ne 0) {
            throw "The unit tests failed under Windows PowerShell 5.1 (exit code $LASTEXITCODE)."
        }
    }
}

$changed = @()
if (Get-Command -Name git -ErrorAction SilentlyContinue) {
    $changed = @(& git -C $repositoryRoot status --porcelain -- $generated)
}
if ($changed.Count -gt 0) {
    Write-Information -InformationAction Continue -MessageData (
        "Build done. Generated files that changed, to commit with their cause:`n$($changed -join "`n")")
} else {
    Write-Information -MessageData 'Build done. No generated file changed.' -InformationAction Continue
}
