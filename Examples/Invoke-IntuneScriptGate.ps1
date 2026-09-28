#Requires -Version 5.1

<#
    .SYNOPSIS
        Runs IntuneScriptLab's analysis as a CI gate: annotations, a job summary and an exit code.

    .DESCRIPTION
        Analyzes every PowerShell script under the given paths with Test-IntuneScript, the way
        Intune will run them (script type, context and bitness from the folder, the file name or a
        directive), then reports for a build:

            - one GitHub Actions annotation per finding (::error, ::warning, ::notice with the file,
              line, column and rule), on by default when GITHUB_ACTIONS is set
            - a Markdown summary appended to the file GITHUB_STEP_SUMMARY names, or to -SummaryPath
            - a SARIF 2.1.0 log at -SarifPath, for github/codeql-action/upload-sarif
            - the findings themselves on the pipeline with -PassThru
            - exit code 1 when any finding reaches -FailOn (Error by default), 0 otherwise

        The script ships in the module's Examples folder and is what the workflow template
        intune-script-gate.yml calls; it works from any runner with the module installed, and from
        a copy of the module checked into a repository (it imports the module next to itself first,
        then by name).

    .PARAMETER Path
        Folders or scripts to analyze; folders are searched for .ps1 files recursively. Default:
        the current directory.

    .PARAMETER FailOn
        The lowest severity that fails the build: Error (default), Warning, Information, or None
        to report without failing.

    .PARAMETER IncludeRule
        Rule names (wildcards allowed) to run; everything else is skipped.

    .PARAMETER ExcludeRule
        Rule names (wildcards allowed) to skip. IslAssumedContext is a common one to exclude once
        the folder layout is settled.

    .PARAMETER ScriptType
        Passed to Test-IntuneScript when every script under -Path is of one type; Auto (default)
        infers per script.

    .PARAMETER Annotate
        Write GitHub Actions annotations. Defaults to on when the GITHUB_ACTIONS variable is set;
        -Annotate:$false silences them.

    .PARAMETER SummaryPath
        The Markdown file to append the summary to. Default: the file named by GITHUB_STEP_SUMMARY,
        or none.

    .PARAMETER Root
        The folder file paths are made relative to in annotations and the summary. Default:
        GITHUB_WORKSPACE, or the current directory.

    .PARAMETER Settings
        A settings file path or hashtable for the analysis. Omitted, the nearest
        IntuneScriptLab.settings.psd1 above each script applies.

    .PARAMETER SarifPath
        Write the findings as a SARIF 2.1.0 log to this file (Export-IntuneFindingSarif), for
        upload to code scanning. Paths inside it are relative to -Root.

    .PARAMETER PassThru
        Also write the IntuneScriptLab.Finding objects to the pipeline.

    .EXAMPLE
        .\Invoke-IntuneScriptGate.ps1 -Path .\Intune

        Analyzes everything under .\Intune and exits 1 if any script has an error-level finding.

    .EXAMPLE
        .\Invoke-IntuneScriptGate.ps1 -Path .\Remediations, .\Win32 -FailOn Warning -ExcludeRule IslAssumedContext

        Fails on warnings too, without the context note.

    .EXAMPLE
        .\Invoke-IntuneScriptGate.ps1 -Path . -FailOn None -PassThru | Group-Object RuleName

        Reports without failing and returns the findings for further processing.

    .INPUTS
        None.

    .OUTPUTS
        IntuneScriptLab.Finding with -PassThru; otherwise nothing on the pipeline. The exit code
        carries the verdict.

    .NOTES
        Author: Jeffrey Stuhr. Annotations use the workflow-command syntax GitHub Actions parses
        from stdout; on any other CI they are plain lines and can be switched off.

    .LINK
        https://docs.github.com/actions/using-workflows/workflow-commands-for-github-actions
#>
[CmdletBinding()]
[OutputType('IntuneScriptLab.Finding')]
# GitHub reads workflow commands (::error, ::warning) from plain stdout lines, which is what
# Write-Host produces; the findings themselves go to the pipeline only with -PassThru
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
param(
    [string[]]$Path = @('.'),

    [ValidateSet('Error', 'Warning', 'Information', 'None')]
    [string]$FailOn = 'Error',

    [string[]]$IncludeRule,

    [string[]]$ExcludeRule,

    [ValidateSet('Auto', 'Detection', 'Remediation', 'PlatformScript', 'Win32Detection', 'Win32Requirement')]
    [string]$ScriptType = 'Auto',

    [switch]$Annotate = [bool]$env:GITHUB_ACTIONS,

    [string]$SummaryPath = $env:GITHUB_STEP_SUMMARY,

    [string]$SarifPath,

    [string]$Root = $(if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }),

    $Settings,

    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'

# The module next to this script when it runs from the module folder, otherwise the installed one
$shipped = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'IntuneScriptLab.psd1'
if (Test-Path -LiteralPath $shipped) { Import-Module $shipped -Force } else { Import-Module IntuneScriptLab }

$severityRank = @{ Information = 0; Warning = 1; Error = 2 }
$annotationLevel = @{ Information = 'notice'; Warning = 'warning'; Error = 'error' }
$rootPath = (Resolve-Path -LiteralPath $Root).ProviderPath.TrimEnd('\', '/')

function Get-RelativePath {
    param([string]$FullPath)
    if ($FullPath.StartsWith($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        $FullPath.Substring($rootPath.Length).TrimStart('\', '/').Replace('\', '/')
    }
    else { $FullPath }
}

function ConvertTo-AnnotationText {
    # Workflow commands take a percent-encoded message on one line
    param([string]$Text)
    $Text.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')
}

$testSplat = @{ Path = $Path; ScriptType = $ScriptType }
if ($PSBoundParameters.ContainsKey('Settings')) { $testSplat.Settings = $Settings }
if ($IncludeRule) { $testSplat.IncludeRule = $IncludeRule }
if ($ExcludeRule) { $testSplat.ExcludeRule = $ExcludeRule }
$findings = @(Test-IntuneScript @testSplat)
$scripts = @($findings | ForEach-Object { $_.ScriptPath } | Sort-Object -Unique)
$counts = @{ Error = 0; Warning = 0; Information = 0 }
foreach ($finding in $findings) { $counts[$finding.Severity]++ }

if ($findings) { $findings | Format-Table | Out-String -Width 200 | Write-Host }
Write-Host ("IntuneScriptLab: $($findings.Count) finding(s) in $($scripts.Count) script(s): " +
    "$($counts.Error) error(s), $($counts.Warning) warning(s), $($counts.Information) note(s)")

if ($Annotate) {
    foreach ($finding in $findings) {
        $location = "file=$(Get-RelativePath -FullPath $finding.ScriptPath)"
        if ($finding.Line -gt 0) { $location += ",line=$($finding.Line),col=$([Math]::Max(1, $finding.Column))" }
        $message = ConvertTo-AnnotationText -Text $finding.Message
        Write-Host "::$($annotationLevel[$finding.Severity]) $location,title=$($finding.RuleName)::$message"
    }
}

if ($SummaryPath) {
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("## IntuneScriptLab: $($findings.Count) finding(s) in $($scripts.Count) script(s)")
    $lines.Add('')
    $lines.Add("$($counts.Error) error(s), $($counts.Warning) warning(s), $($counts.Information) note(s); " +
        "gate: fail on $FailOn.")
    if ($findings) {
        $lines.Add('')
        $lines.Add('| Severity | Rule | Script | Line | Message |')
        $lines.Add('|---|---|---|---:|---|')
        foreach ($finding in $findings) {
            $cell = $finding.Message.Replace('|', '\|') -replace '\r?\n', ' '
            $line = if ($finding.Line -gt 0) { $finding.Line } else { '' }
            $lines.Add("| $($finding.Severity) | $($finding.RuleName) | " +
                "$(Get-RelativePath -FullPath $finding.ScriptPath) | $line | $cell |")
        }
    }
    $lines.Add('')
    $summaryText = ($lines -join "`n") + "`n"
    [System.IO.File]::AppendAllText($SummaryPath, $summaryText, [System.Text.UTF8Encoding]::new($false))
}

if ($SarifPath) {
    $null = Export-IntuneFindingSarif -Finding $findings -Path $SarifPath -Root $rootPath
    Write-Host "SARIF written to $SarifPath"
}

if ($PassThru) { $findings }

# Assigned from an if statement, a one-item array comes back unwrapped on Windows PowerShell 5.1
$failing = @()
if ($FailOn -ne 'None') {
    $failing = @($findings | Where-Object { $severityRank[$_.Severity] -ge $severityRank[$FailOn] })
}
if ($failing.Count) {
    Write-Host "::group::Gate"
    Write-Host "$($failing.Count) finding(s) at $FailOn or above; failing the build"
    Write-Host '::endgroup::'
    exit 1
}
exit 0
