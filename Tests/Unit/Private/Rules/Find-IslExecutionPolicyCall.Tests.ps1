#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The agent launches every script with -ExecutionPolicy Bypass (AgentExecutor.log), so a
    Set-ExecutionPolicy is redundant at process scope and a lasting side effect at any other.
#>

BeforeAll {
    $script:ModuleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Find-IslExecutionPolicyCall' -Tag 'Unit', 'Private', 'Rule' {

    It 'notes a process-scope call as redundant' {
        $body = "Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force`nexit 0"
        $path = New-TestScript 'Detect-P.ps1' $body
        $findings = @(Get-RuleFinding $path IslExecutionPolicyCall)
        $findings.Count | Should-Be 1
        $findings[0].Severity | Should-Be 'Information'
        $findings[0].Message | Should-BeLikeString '*does nothing here*'
    }

    It 'warns about any other scope, named or defaulted' {
        $body = "Set-ExecutionPolicy Unrestricted -Force`n" +
            "Set-ExecutionPolicy -Scope 'CurrentUser' RemoteSigned`nexit 0"
        $path = New-TestScript 'Detect-M.ps1' $body
        $findings = @(Get-RuleFinding $path IslExecutionPolicyCall)
        $findings.Count | Should-Be 2
        $findings.Severity | Should-All { $_ -eq 'Warning' }
        $findings[0].Message | Should-BeLikeString '*scope LocalMachine*'
        $findings[1].Message | Should-BeLikeString '*scope CurrentUser*'
    }

    It 'is silent without the call' {
        $path = New-TestScript 'Detect-N.ps1' "Get-ExecutionPolicy | Out-Null`nexit 0"
        @(Get-RuleFinding $path IslExecutionPolicyCall).Count | Should-Be 0
    }
}
