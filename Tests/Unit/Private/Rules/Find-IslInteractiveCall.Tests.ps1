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

    It 'flags Get-Credential as an error when it is sure to prompt: <Call>' -ForEach @(
        @{ Call = 'Get-Credential' }
        @{ Call = "Get-Credential -Message 'Sign in'" }
        @{ Call = "Get-Credential -UserName admin -Message 'Sign in'" }
        @{ Call = "Get-Credential -Credential 'CONTOSO\admin'" }
        @{ Call = 'Get-Credential admin' }
        @{ Call = 'Get-Credential "$env:USERDOMAIN\admin"' }
        @{ Call = 'Get-Credential $name -Message hello' }
    ) {
        $path = New-TestScript 'script.ps1' "`$c = $Call"
        $findings = @(Get-RuleFinding $path IslInteractiveCall)
        $findings.Count | Should-Be 1
        $findings[0].Severity | Should-Be 'Error'
        $findings[0].Message | Should-BeLikeString 'Get-Credential waits for input*'
    }

    It 'warns when Get-Credential is handed something that may be a built credential: <Call>' -ForEach @(
        @{ Call = 'Get-Credential -Credential $built'; Handed = '$built' }
        @{ Call = 'Get-Credential $built'; Handed = '$built' }
        @{ Call = 'Get-Credential -Cred:$built'; Handed = '$built' }
        @{ Call = 'Get-Credential -ErrorAction Stop -Credential $settings.Account'; Handed = '$settings.Account' }
        @{ Call = 'Get-Credential (Import-Clixml C:\x.xml)'; Handed = '(Import-Clixml C:\x.xml)' }
    ) {
        # A PSCredential is returned as it is (REM-CRED-BUILT); a user name in the same place prompts
        $path = New-TestScript 'script.ps1' "`$c = $Call"
        $findings = @(Get-RuleFinding $path IslInteractiveCall)
        $findings.Count | Should-Be 1
        $findings[0].Severity | Should-Be 'Warning'
        $findings[0].Message | Should-BeLikeString "*already built*if $Handed can ever be a name*30 minutes*"
        $findings[0].Evidence | Should-BeLikeString '*(REM-CRED-BUILT*'
    }

    It 'warns on Set-ExecutionPolicy and Install-Module without -Force or -Confirm:$false' {
        # A bare -Confirm forces the prompt; only -Confirm:$false switches it off
        $path = New-TestScript 'script.ps1' ("Set-ExecutionPolicy RemoteSigned`nInstall-Module Foo -Force`n" +
            "Install-Module Bar`nInstall-Module Baz -Confirm`nInstall-Module Qux -Confirm:`$false")
        $findings = @(Get-RuleFinding $path IslInteractiveCall)
        $findings.Count | Should-Be 3
        @($findings.Text) | Should-ContainCollection 'Install-Module Baz -Confirm'
        @($findings.Text) | Should-NotContainCollection 'Install-Module Qux -Confirm:$false'
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
