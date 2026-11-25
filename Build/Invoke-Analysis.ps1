#Requires -Version 5.1

<#
.SYNOPSIS
    Runs PSScriptAnalyzer over the repository as the tests job does.

.DESCRIPTION
    Analyzes every PowerShell file of the module, the rule module, the examples, the build scripts,
    the tests and the validation kit with the default rules and PSScriptAnalyzerSettings.psd1, at
    Error and Warning. The settings hold the layout rules of the standards, the 115-character line
    among them. The validation kit's three instruments, Probe.ps1, Win32Install.ps1 and
    Fixtures.ps1, keep the layout they ran with in the rounds that cite them
    (Validation/README.md), so they get the default rules only.

    The default rules include the five of PSScriptAnalyzer's ScriptSecurity preset, so this is
    also the static analysis of the security gate. The script writes a table of the findings and
    fails when there is any.

.EXAMPLE
    ./Build/Invoke-Analysis.ps1

    Analyzes the repository and writes how many files it analyzed.

.INPUTS
    None.

.OUTPUTS
    None. A summary, or a table of findings, as information records.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Module -Name PSScriptAnalyzer -ListAvailable)) {
    throw 'PSScriptAnalyzer is not installed: Install-PSResource -Name PSScriptAnalyzer -Version 1.25.0'
}

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$settingsPath = Join-Path -Path $repositoryRoot -ChildPath 'PSScriptAnalyzerSettings.psd1'
$folders = 'Public', 'Private', 'PSScriptAnalyzer', 'Examples', 'Build', 'Tests', 'Validation' |
    ForEach-Object { Join-Path -Path $repositoryRoot -ChildPath $_ }
$rootFiles = 'IntuneScriptLab.psd1', 'IntuneScriptLab.psm1' |
    ForEach-Object { Get-Item -LiteralPath (Join-Path -Path $repositoryRoot -ChildPath $_) }
$files = @(Get-ChildItem -Path $folders -Recurse -Include *.ps1, *.psm1, *.psd1 -File) + @($rootFiles)
$validationFolder = Join-Path -Path $repositoryRoot -ChildPath 'Validation'
$instruments = @('Probe.ps1', 'Win32Install.ps1', 'Fixtures.ps1' |
        ForEach-Object { (Resolve-Path -LiteralPath (Join-Path -Path $validationFolder -ChildPath $_)).Path })

$issues = @(foreach ($file in $files) {
        $analyzerSplat = @{ Path = $file.FullName; Severity = 'Error', 'Warning' }
        if ($file.FullName -notin $instruments) {
            $analyzerSplat['Settings'] = $settingsPath
        }
        Invoke-ScriptAnalyzer @analyzerSplat
    })
if ($issues) {
    $table = $issues | Format-Table -Property RuleName, Severity, ScriptName, Line -AutoSize | Out-String
    Write-Information -MessageData $table -InformationAction Continue
    throw "PSScriptAnalyzer reported $($issues.Count) issue(s)."
}
Write-Information -InformationAction Continue -MessageData (
    "PSScriptAnalyzer clean with PSScriptAnalyzerSettings.psd1 in $($files.Count) files.")
