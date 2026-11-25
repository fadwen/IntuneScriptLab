#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    A script that reboots the device takes the agent down with it before the result is reported;
    Intune expects a reboot to be signalled with an exit code instead.
#>

BeforeAll {
    $script:ModuleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
}

Describe 'Find-IslRebootCommand' -Tag 'Unit', 'Private', 'Rule' {

    It 'flags Restart-Computer and shutdown /r' {
        $path = New-TestScript 'Remediate-R.ps1' "shutdown /r /t 0`nRestart-Computer -Force`nexit 0"
        $findings = @(Get-RuleFinding $path IslRebootCommand)
        $findings.Count | Should-Be 2
        $findings.RuleName | Should-All { $_ -eq 'IslRebootCommand' }
    }

    It 'is silent on a script that only signals the reboot' {
        $path = New-TestScript 'Remediate-Ok.ps1' "Write-Output 'reboot needed'`nexit 3010"
        @(Get-RuleFinding $path IslRebootCommand).Count | Should-Be 0
    }
}
