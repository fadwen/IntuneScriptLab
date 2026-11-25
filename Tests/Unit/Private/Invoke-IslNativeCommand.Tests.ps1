#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The runner for the small system tools, against a real cmd.exe (milliseconds). What matters is
    what the call operator gets wrong on Windows PowerShell 5.1: a line on the error stream must
    come back as text, whatever error preference is in force in the module.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }
    $script:Cmd = Join-Path ([System.Environment]::SystemDirectory) 'cmd.exe'

    function Invoke-NativeCommand {
        <#
        .SYNOPSIS
            Runs Invoke-IslNativeCommand inside the module under a given error preference.

        .DESCRIPTION
            Sets the error preference inside the module, as a caller's -ErrorAction would, and calls
            the private function with the given parameters, so that a test can show that the result
            does not depend on that preference.

        .PARAMETER Parameters
            The parameters of Invoke-IslNativeCommand, FilePath and Arguments.

        .PARAMETER Preference
            The error preference in force inside the module during the call, Continue by default.

        .EXAMPLE
            Invoke-NativeCommand @{ FilePath = $script:Cmd; Arguments = '/D /C "exit 0"' } -Preference Stop

            Runs cmd.exe under the error preference Stop and returns its exit code and output.

        .INPUTS
            None.

        .OUTPUTS
            IntuneScriptLab.NativeCommandResult. What Invoke-IslNativeCommand returns.
        #>
        [CmdletBinding()]
        [OutputType('IntuneScriptLab.NativeCommandResult')]
        param(
            [hashtable]$Parameters,

            [string]$Preference = 'Continue'
        )

        InModuleScope IntuneScriptLab -Parameters @{ Parameters = $Parameters; Preference = $Preference } {
            # What a caller's -ErrorAction leaves in force inside the module
            $ErrorActionPreference = $Preference
            Invoke-IslNativeCommand @Parameters
        }
    }
}

Describe 'Invoke-IslNativeCommand' -Tag 'Unit', 'Private' {

    Context 'Parameter Validation' {
        It 'needs the path of the executable and takes the arguments as one optional string' {
            $command = InModuleScope IntuneScriptLab { Get-Command Invoke-IslNativeCommand }
            $command | Should-HaveParameter -ParameterName FilePath -Type ([string]) -Mandatory
            $command | Should-HaveParameter -ParameterName Arguments -Type ([string])
            $command.Parameters['Arguments'].Attributes.Mandatory | Should-NotContainCollection $true
        }
    }

    Context 'Core Functionality' {
        It 'returns the exit code and what both streams held, under error action <Preference>' -ForEach @(
            @{ Preference = 'Continue' }
            @{ Preference = 'Stop' }
        ) {
            $result = Invoke-NativeCommand -Preference $Preference -Parameters @{
                FilePath = $script:Cmd; Arguments = '/D /C "echo out& echo err 1>&2& exit 3"'
            }

            $result.PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.NativeCommandResult'
            $result.ExitCode | Should-Be 3
            $result.StdOut | Should-Be 'out'
            $result.StdErr | Should-Be 'err'
        }

        It 'returns empty text for a stream the executable did not write to' {
            $result = Invoke-NativeCommand @{ FilePath = $script:Cmd; Arguments = '/D /C "exit 0"' }

            $result.ExitCode | Should-Be 0
            $result.StdOut | Should-Be ''
            $result.StdErr | Should-Be ''
        }
    }

    Context 'Error Handling' {
        It 'ends with a terminating error when the executable cannot be started' {
            $missing = Join-Path $TestDrive 'no-such-tool.exe'

            { Invoke-NativeCommand @{ FilePath = $missing } } |
                Should-Throw -ExceptionType ([System.Management.Automation.MethodInvocationException])
        }
    }
}
