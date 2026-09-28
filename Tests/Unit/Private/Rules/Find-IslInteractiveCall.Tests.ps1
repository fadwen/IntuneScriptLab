#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The agent launches scripts without -NonInteractive and with a hidden console (PS-PROBE-ARGS),
    so a prompt waits for input that never comes until the timeout kills the script.
#>

BeforeAll {
    $script:ModuleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Find-IslInteractiveCall' -Tag 'Unit', 'Private', 'Rule' {

    It 'flags Read-Host, Pause and console reads as errors' {
        $path = New-TestScript 'Detect-I.ps1' "`$a = Read-Host 'x'`nPause`n[Console]::ReadKey()`nexit 0"
        $findings = @(Get-RuleFinding $path IslInteractiveCall)
        $findings.Count | Should-Be 3
        $findings.Severity | Should-All { $_ -eq 'Error' }
    }

    It 'warns on Set-ExecutionPolicy and Install-Module without -Force' {
        $path = New-TestScript 'script.ps1' ("Set-ExecutionPolicy RemoteSigned`nInstall-Module Foo -Force`n" +
            'Install-Module Bar')
        @(Get-RuleFinding $path IslInteractiveCall).Count | Should-Be 2
    }

    It 'names the platform-script timeout' {
        $path = New-TestScript 'script.ps1' 'Read-Host'
        @(Get-RuleFinding $path IslInteractiveCall).Message | Should-BeLikeString '*30 minutes*'
    }

    It 'names the remediation timeout for a detection' {
        $path = New-TestScript 'Detect-Prompt.ps1' 'Read-Host; exit 0'
        @(Get-RuleFinding $path IslInteractiveCall).Message | Should-BeLikeString '*60 minutes*'
    }
}
