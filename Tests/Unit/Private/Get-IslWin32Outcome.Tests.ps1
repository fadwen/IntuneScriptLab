#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    What the agent makes of the exit code of a Win32 install or uninstall.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }
    $script:Codes = @{ 0 = 'success'; 1707 = 'success'; 3010 = 'softReboot'; 1641 = 'hardReboot'; 1618 = 'retry' }

    function script:Get-Outcome {
        param($Run)
        InModuleScope IntuneScriptLab -Parameters @{ Run = $Run; Codes = $script:Codes } {
            Get-IslWin32Outcome -Run $Run -ReturnCodes $Codes
        }
    }
}

Describe 'Get-IslWin32Outcome' -Tag 'Unit', 'Private' {

    It 'gives <Expected> for exit code <ExitCode>' -ForEach @(
        @{ ExitCode = 0; Expected = 'success' }
        @{ ExitCode = 3010; Expected = 'softReboot' }
        @{ ExitCode = 1641; Expected = 'hardReboot' }
        @{ ExitCode = 1618; Expected = 'retry' }
        @{ ExitCode = 1603; Expected = 'failed' }
    ) {
        Get-Outcome -Run ([pscustomobject]@{ TimedOut = $false; ExitCode = $ExitCode }) | Should-Be $Expected
    }

    It 'gives timedOut for a run that was ended, whatever its exit code' {
        Get-Outcome -Run ([pscustomobject]@{ TimedOut = $true; ExitCode = 0 }) | Should-Be 'timedOut'
    }

    It 'gives failed for a run without an exit code' {
        Get-Outcome -Run ([pscustomobject]@{ TimedOut = $false; ExitCode = $null }) | Should-Be 'failed'
    }
}
