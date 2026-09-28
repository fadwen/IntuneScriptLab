#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The PSScriptAnalyzer wrapper: the rules PSScriptAnalyzer discovers in the module's
    PSScriptAnalyzer folder, and the records it produces for a script compared with what
    Test-IntuneScript reports for the same file. Needs PSScriptAnalyzer; skipped where it is not
    installed. Under Windows PowerShell 5.1 the module is imported by path from the PowerShell 7
    module folder when it is not installed for 5.1.
#>

BeforeDiscovery {
    # Discovery decides whether the block runs; BeforeAll repeats the lookup because discovery-time
    # variables do not reach the run
    $script:AnalyzerModule = if (Get-Module -ListAvailable PSScriptAnalyzer) { 'PSScriptAnalyzer' }
    else {
        $childItemSplat = @{
            Path        = Join-Path $env:USERPROFILE 'Documents\PowerShell\Modules\PSScriptAnalyzer'
            Filter      = 'PSScriptAnalyzer.psd1'
            Recurse     = $true
            ErrorAction = 'SilentlyContinue'
        }
        $pwshCopy = Get-ChildItem @childItemSplat | Select-Object -Last 1
        if ($pwshCopy) { $pwshCopy.FullName }
    }
    $script:AnalyzerAvailable = [bool]$script:AnalyzerModule
}

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    $analyzer = if (Get-Module -ListAvailable PSScriptAnalyzer) { 'PSScriptAnalyzer' }
    else {
        $childItemSplat = @{
            Path        = Join-Path $env:USERPROFILE 'Documents\PowerShell\Modules\PSScriptAnalyzer'
            Filter      = 'PSScriptAnalyzer.psd1'
            Recurse     = $true
            ErrorAction = 'SilentlyContinue'
        }
        $pwshCopy = Get-ChildItem @childItemSplat | Select-Object -Last 1
        if ($pwshCopy) { $pwshCopy.FullName }
    }
    if ($analyzer) { Import-Module $analyzer -ErrorAction Stop }
    $script:RulePath = Get-IntuneAnalyzerRulePath
    $script:Detect = Join-Path $TestDrive 'Detect-Widget.ps1'
    $detectBody = @(
        '# IntuneScriptLab: ScriptType=Detection'
        '$item = Get-Item C:\Windows\notepad.exe'
        '$siblings = gci C:\Windows -Filter *.exe'
        'function Get-Helper { 1..3 | ForEach-Object { $_ } }'
        "if (`$item) { return 'found' }"
        'Start-Sleep -Seconds 4000'
        'exit 1'
    ) -join "`r`n"
    [System.IO.File]::WriteAllText($script:Detect, $detectBody, [System.Text.UTF8Encoding]::new($true))
    $script:Direct = @(Test-IntuneScript -Path $script:Detect)
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'PSScriptAnalyzer wrapper' -Tag 'Integration', 'Analyzer' -Skip:(-not $script:AnalyzerAvailable) {

    It 'exposes one Measure- rule per IntuneScriptLab rule, plus the assumed-context note' {
        $rules = @(Get-ScriptAnalyzerRule -CustomRulePath $script:RulePath)
        $expected = @(InModuleScope IntuneScriptLab { $script:RuleOrder } |
            ForEach-Object { $_ -replace '^Find-', 'Measure-' }) + 'Measure-IslAssumedContext'
        @($rules.RuleName | Sort-Object) | Should-BeCollection @($expected | Sort-Object)
        $rules.SourceName | Should-All { $_ -eq 'IntuneScriptLab.Rules' }
    }

    It 'reports the findings Test-IntuneScript reports, once each, with rule, severity and line' {
        $records = @($scriptAnalyzerSplat = @{
                         Path                = $script:Detect
                         CustomRulePath      = $script:RulePath
                         IncludeDefaultRules = $false
                     }
                     Invoke-ScriptAnalyzer @scriptAnalyzerSplat)
        $script:Direct.Count | Should-BeGreaterThan 2
        $records.Count | Should-Be $script:Direct.Count
        # A finding with no extent (line 0) is reported at the root script block, line 1
        $expected = @($script:Direct | ForEach-Object {
                "Measure-$($_.RuleName)@$([Math]::Max(1, $_.Line)):$($_.Severity)"
            } | Sort-Object)
        @($records | ForEach-Object { "$($_.RuleName)@$($_.Line):$($_.Severity)" } | Sort-Object) |
            Should-BeCollection $expected
        ($records | Where-Object RuleName -eq 'Measure-IslExitCodeIssue').Message |
            Should-BeLikeString '*[[]Observed: *'
    }

    It 'points each record at the finding text and keeps the script path' {
        $records = @($scriptAnalyzerSplat = @{
                         Path                = $script:Detect
                         CustomRulePath      = $script:RulePath
                         IncludeDefaultRules = $false
                     }
                     Invoke-ScriptAnalyzer @scriptAnalyzerSplat)
        $sleep = $records | Where-Object RuleName -eq 'Measure-IslLongSleep'
        $sleep.Extent.Text | Should-BeLikeString 'Start-Sleep -Seconds 4000*'
        $sleep.ScriptPath | Should-Be $script:Detect
    }

    It 'honours -ExcludeRule and -IncludeRule with the Measure- names' {
        $without = @($scriptAnalyzerSplat = @{
                         Path                = $script:Detect
                         CustomRulePath      = $script:RulePath
                         IncludeDefaultRules = $false
                         ExcludeRule         = 'Measure-IslAssumedContext'
                     }
                     Invoke-ScriptAnalyzer @scriptAnalyzerSplat)
        $without.RuleName | Should-NotContainCollection 'Measure-IslAssumedContext'
        $without.Count | Should-Be ($script:Direct.Count - 1)
        $only = @($scriptAnalyzerSplat = @{
                      Path                = $script:Detect
                      CustomRulePath      = $script:RulePath
                      IncludeDefaultRules = $false
                      IncludeRule         = 'Measure-IslLongSleep'
                  }
                  Invoke-ScriptAnalyzer @scriptAnalyzerSplat)
        $only.RuleName | Should-All { $_ -eq 'Measure-IslLongSleep' }
        $only.Count | Should-Be 1
    }

    It 'analyzes a -ScriptDefinition the same way, reading the type from the directive' {
        $records = @($scriptAnalyzerSplat = @{
                         ScriptDefinition    = ([System.IO.File]::ReadAllText($script:Detect))
                         CustomRulePath      = $script:RulePath
                         IncludeDefaultRules = $false
                     }
                     Invoke-ScriptAnalyzer @scriptAnalyzerSplat)
        $records.Count | Should-Be $script:Direct.Count
        ($records | Where-Object RuleName -eq 'Measure-IslAssumedContext').Message |
            Should-BeLikeString '*Detection (directive)*'
    }

    It 'runs next to the built-in rules in one pass with -IncludeDefaultRules' {
        # A -CustomRulePath switches the built-in rules off unless -IncludeDefaultRules asks for them
        $records = @($scriptAnalyzerSplat = @{
                         Path                = $script:Detect
                         CustomRulePath      = $script:RulePath
                         IncludeDefaultRules = $true
                     }
                     Invoke-ScriptAnalyzer @scriptAnalyzerSplat)
        $records.RuleName | Should-ContainCollection 'Measure-IslExitCodeIssue'
        $records.RuleName | Should-ContainCollection 'PSAvoidUsingCmdletAliases'
    }
}
