#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Modules a SYSTEM session under the agent does not have: anything outside the in-box list on a
    plain Windows 11 device (REM-PSMODULEPATH), and the gallery install a script tries to do for
    itself (REM-INSTALL-MODULE).
#>

BeforeAll {
    $script:ModuleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Find-IslModuleDependency' -Tag 'Unit', 'Private', 'Rule' {

    It 'warns about Import-Module of a module that is not in-box, by name or by -Name, one per module' {
        $body = "Import-Module ActiveDirectory`n" +
            "Import-Module -Name Az.Accounts, Microsoft.Graph.Authentication`nexit 0"
        $findings = @(Get-RuleFinding (New-TestScript 'Detect-Ad.ps1' $body) IslModuleDependency)
        $findings.Count | Should-Be 3
        $findings.Severity | Should-All { $_ -eq 'Warning' }
        $findings[0].Message | Should-BeLikeString 'Import-Module names ActiveDirectory, which is not in-box*'
        $findings[2].Message | Should-BeLikeString '*Microsoft.Graph.Authentication*'
    }

    It 'is silent for in-box modules, paths, wildcards and variables' {
        $body = @(
            'Import-Module Microsoft.PowerShell.Utility'
            'Import-Module ScheduledTasks, BitLocker'
            'Import-Module C:\Tools\Helper.psm1'
            'Import-Module .\lib.psd1'
            'Import-Module $moduleName'
            "Import-Module 'Net*'"
            'exit 0'
        ) -join "`n"
        @(Get-RuleFinding (New-TestScript 'Detect-Ok.ps1' $body) IslModuleDependency).Count | Should-Be 0
    }

    It 'reads #Requires -Modules and using module' {
        $body = "#Requires -Modules ActiveDirectory, @{ ModuleName = 'PSReadLine'; ModuleVersion = '2.0' }`n" +
            "using module Pester`nexit 0"
        $findings = @(Get-RuleFinding (New-TestScript 'Detect-Req.ps1' $body) IslModuleDependency)
        $findings.Count | Should-Be 1
        $findings[0].Message | Should-BeLikeString '#Requires -Modules names ActiveDirectory*'
    }

    It 'warns about installing from the gallery inside the script' {
        $body = "Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser`nInstall-PSResource Pester`nexit 0"
        $findings = @(Get-RuleFinding (New-TestScript 'Detect-Inst.ps1' $body) IslModuleDependency)
        $findings.Count | Should-Be 2
        $findings[0].Message | Should-BeLikeString 'Install-Module inside the script installs from the gallery*'
        $findings[1].Message | Should-BeLikeString 'Install-PSResource inside*'
    }
}
