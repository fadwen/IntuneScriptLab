#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Timeouts observed: 30 minutes for platform scripts, 60 for remediations and Win32
    (PS-TIMEOUT, REM-TIMEOUT). A sleep that eats a large share of that is graded against the
    script type's limit.
#>

BeforeAll {
    $script:ModuleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Find-IslLongSleep' -Tag 'Unit', 'Private', 'Rule' {

    It 'grades sleeps against the platform script timeout' {
        $path = New-TestScript 'script.ps1' ("Start-Sleep -Seconds 400`nStart-Sleep 1900`n" +
            'Start-Sleep -Milliseconds 100')
        $findings = @(Get-RuleFinding $path IslLongSleep)
        @($findings | Where-Object Severity -eq 'Warning').Count | Should-Be 1
        @($findings | Where-Object Severity -eq 'Error').Count | Should-Be 1
    }

    It 'is silent on short sleeps' {
        $path = New-TestScript 'script.ps1' "Start-Sleep -Seconds 5`nStart-Sleep -Milliseconds 500"
        @(Get-RuleFinding $path IslLongSleep).Count | Should-Be 0
    }
}
