#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The requirement harness with the process launch mocked: the launch shape it asks for and the
    result it builds from the comparison. The comparison itself is tested in
    Tests\Unit\Private\Compare-IslRequirementOutput.Tests.ps1; real launches in Tests\Integration.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
    $script:Script = 'C:\lab\requirement.ps1'
    $osArchitecture = "$([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)"
    $script:Native = if ($osArchitecture -eq 'Arm64') { 'arm64' } else { 'x64' }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-IntuneRequirementTest' -Tag 'Unit', 'Public' {

    Context 'Parameter Validation' {
        It 'requires the path, the output type and the value; the operator defaults to Equal' {
            $command = Get-Command Invoke-IntuneRequirementTest
            foreach ($name in 'Path', 'OutputType', 'Value') {
                $command.Parameters[$name].Attributes.Mandatory | Should-ContainCollection $true
            }
            $command.Parameters['OutputType'].Attributes.ValidValues |
                Should-BeCollection @('String', 'DateTime', 'Integer', 'Float', 'Version', 'Boolean')
            $command.Parameters['Operator'].Attributes.ValidValues.Count | Should-Be 6
        }

        It 'takes script paths from the pipeline, with the rule given once' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab {
                [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = 'ok'; StdErr = '' }
            }
            $results = @('C:\lab\a.ps1', 'C:\lab\b.ps1' |
                    Invoke-IntuneRequirementTest -OutputType String -Operator Equal -Value ok)
            $results.Count | Should-Be 2
            $results.Applicable | Should-All { $_ }
        }

        It 'defaults to the 64-bit host this device has, as the portal does for requirement rules' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab {
                [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = "ok`r`n"; StdErr = '' }
            }
            $result = Invoke-IntuneRequirementTest -Path $script:Script -OutputType String -Value 'ok'
            $result.Architecture | Should-Be $script:Native
            $result.Context | Should-Be 'User'
            $result.Operator | Should-Be 'Equal'
            Should-Invoke Invoke-IslScriptRun -ModuleName IntuneScriptLab -Exactly -Times 1 -ParameterFilter {
                $Architecture -in 'x64', 'arm64' -and $Phase -eq 'requirement'
            }
        }
    }

    Context 'Core Functionality' {
        It 'reports Applicable with the compared output when the rule is met' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab {
                [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = "2.10.0`r`n"; StdErr = '' }
            }
            $intuneRequirementTestSplat = @{
                Path       = $script:Script
                OutputType = 'Version'
                Operator   = 'GreaterThanOrEqual'
                Value      = '2.9.0'
            }
            $result = Invoke-IntuneRequirementTest @intuneRequirementTestSplat
            $result.Applicable | Should-BeTrue
            $result.Output | Should-Be '2.10.0'
            $result.Reason | Should-BeLikeString "Output '2.10.0' meets Version GreaterThanOrEqual '2.9.0'"
            $result.PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.RequirementResult'
        }

        It 'reports not applicable with the reason when the rule fails' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab {
                [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = "first`r`nok`r`n"; StdErr = '' }
            }
            $result = Invoke-IntuneRequirementTest -Path $script:Script -OutputType String -Value 'ok'
            $result.Applicable | Should-BeFalse
            $result.Reason | Should-BeLikeString "*does not meet String Equal 'ok'"
            $result.StdOut | Should-Be "first`r`nok`r`n"
        }

        It 'carries the rule and the run details on the result' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab {
                [pscustomobject]@{
                    ExitCode = 0; TimedOut = $false; StdOut = "5`r`n"; StdErr = ''; Host = 'h'; ScriptPath = 's'
                    Duration = [timespan]::FromSeconds(2)
                }
            }
            $intuneRequirementTestSplat = @{
                Path           = $script:Script
                OutputType     = 'Integer'
                Operator       = 'GreaterThan'
                Value          = '3'
                Architecture   = 'x86'
                TimeoutSeconds = 9
            }
            $result = Invoke-IntuneRequirementTest @intuneRequirementTestSplat
            $result.OutputType | Should-Be 'Integer'
            $result.Value | Should-Be '3'
            $result.Host | Should-Be 'h'
            $result.Duration.TotalSeconds | Should-Be 2
            Should-Invoke Invoke-IslScriptRun -ModuleName IntuneScriptLab -ParameterFilter {
                $TimeoutSeconds -eq 9
            }
        }
    }

    Context 'Error Handling' {
        It 'reports a timeout as not applicable' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab {
                [pscustomobject]@{ ExitCode = $null; TimedOut = $true; StdOut = ''; StdErr = '' }
            }
            $result = Invoke-IntuneRequirementTest -Path $script:Script -OutputType String -Value 'ok'
            $result.Applicable | Should-BeFalse
            $result.TimedOut | Should-BeTrue
            $result.Reason | Should-BeLikeString 'Timed out*'
        }
    }
}
