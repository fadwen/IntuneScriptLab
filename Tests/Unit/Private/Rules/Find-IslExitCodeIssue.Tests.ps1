#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Exit code traps observed on real devices: a script-scope return before exit 1 is exit 0
    (REM-RETURN), any non-zero exit means "issue found" (REM-EXIT-2, REM-EXIT-NEG), and an
    unhandled throw is exit 1.
#>

BeforeAll {
    $script:ModuleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Find-IslExitCodeIssue' -Tag 'Unit', 'Private', 'Rule' {

    It 'flags return-before-exit in a detection as an error' {
        $path = New-TestScript 'Detect-R.ps1' "Write-Output 'found 1'`nreturn 1`nexit 1"
        $findings = @(Get-RuleFinding $path IslExitCodeIssue)
        @($findings | Where-Object { $_.Severity -eq 'Error' -and $_.Message -like '*return*' }).Count |
            Should-Be 1
    }

    It 'warns on exit codes other than 0 and 1 in a detection' {
        $path = New-TestScript 'Detect-X.ps1' 'if (1) { exit 2 } else { exit -1 }'
        @(Get-RuleFinding $path IslExitCodeIssue | Where-Object Message -like '*non-zero*').Count | Should-Be 2
    }

    It 'warns when a detection has no exit at all' {
        $path = New-TestScript 'Detect-N.ps1' "Write-Output 'checked'"
        @(Get-RuleFinding $path IslExitCodeIssue).Message | Should-BeLikeString '*No exit statement*'
    }

    It 'warns on an unhandled throw but not on one inside try/catch' {
        $path = New-TestScript 'Detect-Th.ps1' "try { throw 'x' } catch { exit 1 }`nthrow 'y'`nexit 0"
        @(Get-RuleFinding $path IslExitCodeIssue | Where-Object Message -like '*throw*').Count | Should-Be 1
    }

    It 'ignores return inside a function' {
        $path = New-TestScript 'Detect-F.ps1' "function Get-X { return 1 }`nif (Get-X) { exit 1 }`nexit 0"
        @(Get-RuleFinding $path IslExitCodeIssue | Where-Object Message -like '*return*').Count | Should-Be 0
    }

    It 'does not apply to platform scripts' {
        $path = New-TestScript 'script.ps1' 'exit 5'
        @(Get-RuleFinding $path IslExitCodeIssue).Count | Should-Be 0
    }
}
