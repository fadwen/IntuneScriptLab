#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    What the agent makes of the exit code of a Win32 install or uninstall.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }
    $script:Codes = @{ 0 = 'success'; 1707 = 'success'; 3010 = 'softReboot'; 1641 = 'hardReboot'; 1618 = 'retry' }

    function script:Get-Outcome {
        <#
        .SYNOPSIS
            Gets the outcome Get-IslWin32Outcome gives a run, with the suite's return codes.

        .DESCRIPTION
            Calls the private function inside the module with the run and the return codes in
            $script:Codes.

        .PARAMETER Run
            An object with the TimedOut and ExitCode of an install or uninstall run.

        .EXAMPLE
            Get-Outcome -Run ([pscustomobject]@{ TimedOut = $false; ExitCode = 3010 })

            Returns softReboot.

        .INPUTS
            None.

        .OUTPUTS
            System.String. What Get-IslWin32Outcome returns.
        #>
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [object]$Run
        )

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
