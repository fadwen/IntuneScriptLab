#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The agent's working directory is C:\WINDOWS\system32 and the script runs from a cache copy
    (PS-PROBE-CWD), so relative paths and $PWD point somewhere the author did not intend.
#>

BeforeAll {
    $script:ModuleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Find-IslRelativePath' -Tag 'Unit', 'Private', 'Rule' {

    It 'flags relative paths and $PWD' {
        $path = New-TestScript 'script.ps1' "Get-Content '.\config.json'`n`$x = `$PWD"
        @(Get-RuleFinding $path IslRelativePath).Count | Should-Be 2
    }

    It 'is silent on absolute paths and $PSScriptRoot' {
        $path = New-TestScript 'script.ps1' "Get-Content 'C:\ProgramData\app\config.json'`n`$x = `$PSScriptRoot"
        @(Get-RuleFinding $path IslRelativePath).Count | Should-Be 0
    }
}
