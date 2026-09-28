#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The SARIF export: one run with the tool, a rule entry per rule seen with its help text, a result
    per finding with the relative location, the level, the evidence and an in-source suppression
    where a directive silenced it. Findings come from real analyses so the shapes are the real ones.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
    $script:Repo = Join-Path $TestDrive 'repo'
    $null = New-Item -ItemType Directory -Path (Join-Path $script:Repo 'Remediations\My Widget') -Force
    $body = @(
        '# IntuneScriptLab: ScriptType=Detection'
        "if (Test-Path C:\x) { return 'ok' }"
        'Start-Sleep -Seconds 4000   # IntuneScriptLab: Suppress=IslLongSleep'
        'exit 1'
    ) -join "`r`n"
    $script:Detect = Join-Path $script:Repo 'Remediations\My Widget\Detect.ps1'
    [System.IO.File]::WriteAllText($script:Detect, $body, [System.Text.UTF8Encoding]::new($true))
    $script:Findings = @(Test-IntuneScript -Path $script:Detect -IncludeSuppressed)

    function script:Read-Sarif {
        param([string]$Path)
        Get-Content $Path -Raw | ConvertFrom-Json
    }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Export-IntuneFindingSarif' -Tag 'Unit', 'Public' {

    It 'writes a SARIF 2.1.0 log with the tool, its version and one rule per rule seen' {
        $out = Join-Path $TestDrive 'out\results.sarif'
        $file = Export-IntuneFindingSarif -Finding $script:Findings -Path $out -Root $script:Repo
        $file.FullName | Should-Be $out
        $sarif = Read-Sarif $out
        $sarif.version | Should-Be '2.1.0'
        $sarif.'$schema' | Should-BeLikeString '*sarif-2.1.0.json'
        $run = $sarif.runs[0]
        $run.tool.driver.name | Should-Be 'IntuneScriptLab'
        $run.tool.driver.version | Should-Be ((Get-Module IntuneScriptLab).Version.ToString())
        $expectedRules = @($script:Findings.RuleName | Sort-Object -Unique)
        @($run.tool.driver.rules.id) | Should-BeCollection $expectedRules
        $exitRule = $run.tool.driver.rules | Where-Object id -eq 'IslExitCodeIssue'
        $exitRule.shortDescription.text | Should-BeLikeString '*exit*'
        $exitRule.fullDescription.text | Should-BeLikeString '*return*'
        $exitRule.defaultConfiguration.level | Should-Be 'warning'
    }

    It 'writes one result per finding with the relative location, level, snippet and evidence' {
        $out = Join-Path $TestDrive 'results.sarif'
        $null = Export-IntuneFindingSarif -Finding $script:Findings -Path $out -Root $script:Repo
        $run = (Read-Sarif $out).runs[0]
        @($run.results).Count | Should-Be $script:Findings.Count
        $exit = $run.results | Where-Object ruleId -eq 'IslExitCodeIssue'
        $exit.level | Should-Be 'error'
        $exit.ruleIndex | Should-Be ([array]::IndexOf(@($run.tool.driver.rules.id), 'IslExitCodeIssue'))
        $location = $exit.locations[0].physicalLocation
        $location.artifactLocation.uri | Should-Be 'Remediations/My%20Widget/Detect.ps1'
        $location.artifactLocation.uriBaseId | Should-Be '%SRCROOT%'
        $location.region.startLine | Should-Be 2
        $location.region.startColumn | Should-BeGreaterThan 0
        $location.region.snippet.text | Should-BeLikeString "return 'ok'*"
        $exit.properties.evidence | Should-NotBeWhiteSpaceString
        $exit.properties.scriptType | Should-Be 'Detection'
        $run.originalUriBaseIds.'%SRCROOT%'.uri | Should-BeLikeString 'file:///*repo/'
    }

    It 'marks a suppressed finding as suppressed in source and leaves the others unmarked' {
        $out = Join-Path $TestDrive 'suppressed.sarif'
        $null = Export-IntuneFindingSarif -Finding $script:Findings -Path $out -Root $script:Repo
        $run = (Read-Sarif $out).runs[0]
        $sleep = $run.results | Where-Object ruleId -eq 'IslLongSleep'
        $sleep.suppressions[0].kind | Should-Be 'inSource'
        $exit = $run.results | Where-Object ruleId -eq 'IslExitCodeIssue'
        $exit.PSObject.Properties.Name | Should-NotContainCollection 'suppressions'
    }

    It 'takes findings from the pipeline and writes a valid empty log for none' {
        $out = Join-Path $TestDrive 'piped.sarif'
        $null = $script:Findings | Export-IntuneFindingSarif -Path $out -Root $script:Repo
        @((Read-Sarif $out).runs[0].results).Count | Should-Be $script:Findings.Count
        $empty = Join-Path $TestDrive 'empty.sarif'
        $null = Export-IntuneFindingSarif -Finding @() -Path $empty -Root $script:Repo
        $sarif = Read-Sarif $empty
        @($sarif.runs[0].results).Count | Should-Be 0
        @($sarif.runs[0].tool.driver.rules).Count | Should-Be 0
    }

    It 'keeps the absolute path for a file outside the root and maps Information to note' {
        $elsewhere = New-TestScript 'Detect-Far.ps1' 'Write-Host "x"; exit 0'
        $findings = @(Test-IntuneScript -Path $elsewhere)
        $out = Join-Path $TestDrive 'far.sarif'
        $null = Export-IntuneFindingSarif -Finding $findings -Path $out -Root $script:Repo
        $run = (Read-Sarif $out).runs[0]
        $note = $run.results | Where-Object ruleId -eq 'IslAssumedContext'
        $note.level | Should-Be 'note'
        $note.locations[0].physicalLocation.region.startLine | Should-Be 1
        $note.locations[0].physicalLocation.artifactLocation.uri | Should-BeLikeString '*Detect-Far.ps1'
        $note.locations[0].physicalLocation.artifactLocation.uri | Should-NotBeLikeString 'Remediations*'
    }
}
