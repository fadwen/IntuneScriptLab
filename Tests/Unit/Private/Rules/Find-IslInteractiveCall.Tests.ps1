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
        @{ Call = 'Get-Credential (Get-Thing)'; Handed = '(Get-Thing)' }
    ) {
        # A PSCredential is returned as it is (REM-CRED-BUILT); a user name in the same place prompts
        $path = New-TestScript 'script.ps1' "`$c = $Call"
        $findings = @(Get-RuleFinding $path IslInteractiveCall)
        $findings.Count | Should-Be 1
        $findings[0].Severity | Should-Be 'Warning'
        $findings[0].Message | Should-BeLikeString "*already built*if $Handed can ever be a name*30 minutes*"
        $findings[0].Evidence | Should-BeLikeString '*(REM-CRED-BUILT*'
    }

    It 'notes Get-Credential -Credential when what it is handed can only be a credential: <Script>' -ForEach @(
        @{ Script = "`$c = Import-Clixml C:\x.xml`nGet-Credential -Credential `$c"; Source = 'Import-Clixml' }
        @{ Script = "`$c = [pscredential]::new('a', `$s)`nGet-Credential `$c"; Source = '[pscredential]::new()' }
        @{ Script = "`$c = New-Object System.Management.Automation.PSCredential 'a', `$s`nGet-Credential `$c"
            Source = 'New-Object PSCredential' }
        @{ Script = "`$c = New-Object -TypeName PSCredential -ArgumentList 'a', `$s`nGet-Credential -Cred:`$c"
            Source = 'New-Object PSCredential' }
        @{ Script = "[pscredential]`$c = Get-Thing`nGet-Credential `$c"; Source = 'a [pscredential] variable' }
        @{ Script = "param([pscredential]`$Credential)`nGet-Credential `$Credential"
            Source = 'a [pscredential] parameter' }
        @{ Script = "param([System.Management.Automation.PSCredential]`$Credential)`nGet-Credential `$Credential"
            Source = 'a [pscredential] parameter' }
        @{ Script = "`$script:c = (Import-Clixml x)`nGet-Credential `$c"; Source = 'Import-Clixml' }
        @{ Script = "`$c = Import-Clixml x`n`$c = [pscredential]::new('a', `$s)`nGet-Credential `$c"
            Source = 'Import-Clixml, [pscredential]::new()' }
        @{ Script = 'Get-Credential (Import-Clixml C:\x.xml)'; Source = 'Import-Clixml' }
        @{ Script = "Get-Credential ([pscredential]::new('a', `$s))"; Source = '[pscredential]::new()' }
        @{ Script = 'Get-Credential ([pscredential]$x)'; Source = 'a [pscredential] cast' }
    ) {
        # Every value the argument can take is a PSCredential, which Get-Credential returns as it is
        # (REM-CRED-BUILT): the call cannot prompt, so the finding is a note
        $path = New-TestScript 'script.ps1' $Script
        $findings = @(Get-RuleFinding $path IslInteractiveCall)
        $findings.Count | Should-Be 1
        $findings[0].Severity | Should-Be 'Information'
        # The brackets in a source are text, not a wildcard class
        $expected = "*as it is: it comes from $([WildcardPattern]::Escape($Source)), so*"
        $findings[0].Message | Should-BeLikeString $expected
        $findings[0].Evidence | Should-BeLikeString '*(REM-CRED-BUILT*'
    }

    It 'keeps the warning when a value handed to Get-Credential could be something else: <Script>' -ForEach @(
        @{ Script = "`$c = Import-Clixml x`n`$c = 'admin'`nGet-Credential `$c" }
        @{ Script = "param([string]`$Credential)`nGet-Credential `$Credential" }
        @{ Script = "param(`$Credential)`n`$Credential = Import-Clixml x`nGet-Credential `$Credential" }
        @{ Script = "`$c = Import-Clixml x | Select-Object -First 1`nGet-Credential `$c" }
        @{ Script = "`$c = Get-Thing`nGet-Credential `$c" }
        @{ Script = "`$c = New-Object -ComObject Shell.Application`nGet-Credential `$c" }
        @{ Script = "`$c = [string]`$x`nGet-Credential `$c" }
        @{ Script = 'Get-Credential $never' }
    ) {
        # An untyped parameter, a second assignment, a pipeline or a call: one of its values may be a name
        $path = New-TestScript 'script.ps1' $Script
        $findings = @(Get-RuleFinding $path IslInteractiveCall)
        $findings.Count | Should-Be 1
        $findings[0].Severity | Should-Be 'Warning'
        $findings[0].Message | Should-BeLikeString '*can ever be a name*'
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
