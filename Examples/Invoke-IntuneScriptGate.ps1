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
        Folders or scripts to analyze; folders are searched for .ps1 files recursively, leaving out
        Pester suites (*.Tests.ps1), which the suite template places next to the scripts, and the
        contents of a Win32 app's Package folder (Win32\<app>\Package\, what becomes the .intunewin),
        which the agent runs through the install command rather than as a script. A file named
        directly is analyzed. Each path is literal: wildcards are not expanded, so name a folder
        to analyze everything in it. Default: the current directory.

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
    <#
    .SYNOPSIS
        Gets a path relative to the gate's root, with forward slashes.

    .DESCRIPTION
        The findings and the annotations name each file relative to -Root, the folder the script
        resolved into $rootPath, so that GitHub can place an annotation on the file. A path outside
        the root stays as it is.

    .PARAMETER FullPath
        The full path of an analyzed file.

    .EXAMPLE
        Get-RelativePath -FullPath (Join-Path $rootPath 'Intune\Detect.ps1')

        Returns 'Intune/Detect.ps1'.

    .INPUTS
        None.

    .OUTPUTS
        System.String. The relative path, or the full path when it is outside the root.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$FullPath
    )

    if ($FullPath.StartsWith($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        $FullPath.Substring($rootPath.Length).TrimStart('\', '/').Replace('\', '/')
    } else { $FullPath }
}


function Write-GateLine {
    <#
    .SYNOPSIS
        Writes one line of the gate's output to the console.

    .DESCRIPTION
        GitHub reads workflow commands (::error, ::warning) from plain lines of stdout, which is
        where the host writes an information record. The success stream stays for the findings,
        which go to the pipeline only with -PassThru.

    .PARAMETER Text
        The line to write. An empty string writes an empty line.

    .EXAMPLE
        Write-GateLine -Text '::error file=Detect.ps1,line=3::Exit code is missing'

        Writes a workflow command that GitHub shows as an annotation.

    .INPUTS
        None.

    .OUTPUTS
        None. The line is an information record.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    Write-Information -MessageData $Text -InformationAction Continue
}


function ConvertTo-AnnotationText {
    <#
    .SYNOPSIS
        Encodes a message for a GitHub workflow command.

    .DESCRIPTION
        Workflow commands take a percent-encoded message on one line: '%', carriage return and line
        feed are written as %25, %0D and %0A.

    .PARAMETER Text
        The message. Nothing, or an empty string, gives an empty string.

    .EXAMPLE
        ConvertTo-AnnotationText -Text "Line one`nLine two"

        Returns 'Line one%0ALine two'.

    .INPUTS
        None.

    .OUTPUTS
        System.String. The encoded message.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string]$Text
    )

    $Text.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')
}


function ConvertTo-AnnotationProperty {
    <#
    .SYNOPSIS
        Encodes a property value of a GitHub workflow command.

    .DESCRIPTION
        A property value (file=, title=) is encoded as a message is, and its ':' and ',' as well,
        because they delimit the command: a path outside -Root, which stays absolute, would
        otherwise end the property list at its drive letter.

    .PARAMETER Text
        The property value. Nothing, or an empty string, gives an empty string.

    .EXAMPLE
        ConvertTo-AnnotationProperty -Text 'C:\Scripts\Detect.ps1'

        Returns 'C%3A\Scripts\Detect.ps1'.

    .INPUTS
        None.

    .OUTPUTS
        System.String. The encoded value.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string]$Text
    )

    (ConvertTo-AnnotationText -Text $Text).Replace(':', '%3A').Replace(',', '%2C')
}


# Folders are searched here rather than by Test-IntuneScript, so that two kinds of file the suite
# template puts under the script folders are not analyzed as Intune scripts: a Pester suite next to
# the scripts (IntuneScripts.Tests.ps1) and the contents of a Win32 app's Package folder
# (Win32\<app>\Package\), which become the .intunewin and run through the install command as
# SYSTEM, where an install.ps1 would otherwise be read as a user-context platform script. A file
# named directly on -Path is still analyzed. Only the singular segment 'Package' is left out: a
# 'Packages' folder is one that holds Win32 apps, and their detection scripts stay in.
$scriptFiles = @(foreach ($item in $Path) {
        foreach ($resolved in (Resolve-Path -LiteralPath $item)) {
            if (Test-Path -LiteralPath $resolved.ProviderPath -PathType Container) {
                Get-ChildItem -LiteralPath $resolved.ProviderPath -Recurse -Filter *.ps1 -File |
                    Where-Object {
                        $_.Name -notlike '*.Tests.ps1' -and
                        "$($_.DirectoryName)\" -notmatch '(?i)[\\/]Package[\\/]'
                    } | ForEach-Object { $_.FullName }
            } else { $resolved.ProviderPath }
        }
    })
# -ErrorAction Stop: the analysis reports a script it cannot read and goes on with the others,
# and a gate must not pass on scripts that were not analyzed. The preference set above does not
# reach a module's command unless this script runs in the global scope
$testSplat = @{ Path = $scriptFiles; ScriptType = $ScriptType; ErrorAction = 'Stop' }
if ($PSBoundParameters.ContainsKey('Settings')) { $testSplat.Settings = $Settings }
if ($IncludeRule) { $testSplat.IncludeRule = $IncludeRule }
if ($ExcludeRule) { $testSplat.ExcludeRule = $ExcludeRule }
$findings = if ($scriptFiles.Count) { @(Test-IntuneScript @testSplat) } else { @() }
$scripts = @($findings | ForEach-Object { $_.ScriptPath } | Sort-Object -Unique)
$counts = @{ Error = 0; Warning = 0; Information = 0 }
foreach ($finding in $findings) { $counts[$finding.Severity]++ }

if ($findings) { Write-GateLine -Text ($findings | Format-Table | Out-String -Width 200) }
Write-GateLine -Text ("IntuneScriptLab: $($findings.Count) finding(s) in $($scripts.Count) script(s): " +
    "$($counts.Error) error(s), $($counts.Warning) warning(s), $($counts.Information) note(s)")

if ($Annotate) {
    foreach ($finding in $findings) {
        $location = "file=$(ConvertTo-AnnotationProperty -Text (Get-RelativePath -FullPath $finding.ScriptPath))"
        if ($finding.Line -gt 0) { $location += ",line=$($finding.Line),col=$([Math]::Max(1, $finding.Column))" }
        $message = ConvertTo-AnnotationText -Text $finding.Message
        $title = ConvertTo-AnnotationProperty -Text $finding.RuleName
        Write-GateLine -Text "::$($annotationLevel[$finding.Severity]) $location,title=${title}::$message"
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
    Write-GateLine -Text "SARIF written to $SarifPath"
}

if ($PassThru) { $findings }

# Assigned from an if statement, a one-item array comes back unwrapped on Windows PowerShell 5.1
$failing = @()
if ($FailOn -ne 'None') {
    $failing = @($findings | Where-Object { $severityRank[$_.Severity] -ge $severityRank[$FailOn] })
}
if ($failing.Count) {
    Write-GateLine -Text '::group::Gate'
    Write-GateLine -Text "$($failing.Count) finding(s) at $FailOn or above; failing the build"
    Write-GateLine -Text '::endgroup::'
    exit 1
}
exit 0
