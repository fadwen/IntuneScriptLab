#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The requirement harness with the process launch mocked: the launch shape it asks for and the
    result it builds from the comparison. The comparison itself is tested in
    Tests\Unit\Private\Compare-IslRequirementOutput.Tests.ps1; real launches in Tests\Integration.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
    $script:Script = 'C:\lab\requirement.ps1'
    $osArchitecture = "$([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)"
    $script:Native = if ($osArchitecture -eq 'Arm64') { 'arm64' } else { 'x64' }
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
                ConvertTo-FakeRunResult @{ ExitCode = 0; TimedOut = $false; StdOut = 'ok'; StdErr = '' }
            }
            $results = @('C:\lab\a.ps1', 'C:\lab\b.ps1' |
                    Invoke-IntuneRequirementTest -OutputType String -Operator Equal -Value ok)
            $results.Count | Should-Be 2
            $results.Applicable | Should-All { $_ }
        }

        It 'takes several script paths as an array, one result each, as from the pipeline' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab {
                ConvertTo-FakeRunResult @{
                    ExitCode = 0; TimedOut = $false; StdOut = 'ok'; StdErr = ''; ScriptPath = $Path
                }
            }
            $requirementSplat = @{ Path = 'C:\lab\a.ps1', 'C:\lab\b.ps1'; OutputType = 'String'; Value = 'ok' }
            $results = @(Invoke-IntuneRequirementTest @requirementSplat)
            $results.Count | Should-Be 2
            $results[0].ScriptPath | Should-Be 'C:\lab\a.ps1'
            $results[1].ScriptPath | Should-Be 'C:\lab\b.ps1'
            $results.Applicable | Should-All { $_ }
        }

        It 'defaults to the 64-bit host this device has, as the portal does for requirement rules' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab {
                ConvertTo-FakeRunResult @{ ExitCode = 0; TimedOut = $false; StdOut = "ok`r`n"; StdErr = '' }
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
                ConvertTo-FakeRunResult @{ ExitCode = 0; TimedOut = $false; StdOut = "2.10.0`r`n"; StdErr = '' }
            }
            $intuneRequirementTestSplat = @{
                Path = $script:Script
                OutputType = 'Version'
                Operator = 'GreaterThanOrEqual'
                Value = '2.9.0'
            }
            $result = Invoke-IntuneRequirementTest @intuneRequirementTestSplat
            $result.Applicable | Should-BeTrue
            $result.Output | Should-Be '2.10.0'
            $result.Reason | Should-BeLikeString "Output '2.10.0' meets Version GreaterThanOrEqual '2.9.0'"
            $result.PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.RequirementResult'
        }

        It 'reports not applicable with the reason when the rule fails' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab {
                ConvertTo-FakeRunResult @{ ExitCode = 0; StdOut = "first`r`nok`r`n" }
            }
            $result = Invoke-IntuneRequirementTest -Path $script:Script -OutputType String -Value 'ok'
            $result.Applicable | Should-BeFalse
            $result.Reason | Should-BeLikeString "*does not meet String Equal 'ok'"
            $result.StdOut | Should-Be "first`r`nok`r`n"
        }

        It 'carries the rule and the run details on the result' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab {
                ConvertTo-FakeRunResult @{
                    ExitCode = 0; TimedOut = $false; StdOut = "5`r`n"; StdErr = ''; Host = 'h'; ScriptPath = 's'
                    Duration = [timespan]::FromSeconds(2)
                }
            }
            $intuneRequirementTestSplat = @{
                Path = $script:Script
                OutputType = 'Integer'
                Operator = 'GreaterThan'
                Value = '3'
                Architecture = 'x86'
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
                ConvertTo-FakeRunResult @{ ExitCode = $null; TimedOut = $true; StdOut = ''; StdErr = '' }
            }
            $result = Invoke-IntuneRequirementTest -Path $script:Script -OutputType String -Value 'ok'
            $result.Applicable | Should-BeFalse
            $result.TimedOut | Should-BeTrue
            $result.Reason | Should-BeLikeString 'Timed out*'
        }

        It 'reports a script that cannot be run and goes on with the next one from the pipeline' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab {
                ConvertTo-FakeRunResult @{ ExitCode = 0; TimedOut = $false; StdOut = 'ok'; StdErr = '' }
            }
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab -ParameterFilter { $Path -like '*broken*' } {
                throw 'The host could not be started.'
            }

            $output = 'C:\lab\broken.ps1', $script:Script |
                Invoke-IntuneRequirementTest -OutputType String -Value 'ok' -ErrorAction Continue 2>&1
            $errors = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $results = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })

            $errors | Should-BeCollection -Count 1
            $errors[0].Exception.Message | Should-BeLikeString '*host could not be started*'
            $results | Should-BeCollection -Count 1
            $results[0].Applicable | Should-BeTrue
        }

        It 'ends at the script that cannot be run when the caller asks it to stop' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab { throw 'The host could not be started.' }
            $requirementSplat = @{ OutputType = 'String'; Value = 'ok'; ErrorAction = 'Stop' }

            { 'C:\lab\broken.ps1', $script:Script | Invoke-IntuneRequirementTest @requirementSplat } |
                Should-Throw -ExceptionMessage '*host could not be started*'
            Should-Invoke Invoke-IslScriptRun -ModuleName IntuneScriptLab -Times 1 -Exactly
        }

        It 'refuses -Credential with Context System before anything runs' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab { }
            $secure = [securestring]::new()
            foreach ($char in 'pw'.ToCharArray()) { $secure.AppendChar($char) }
            $requirementSplat = @{
                Path = $script:Script; OutputType = 'String'; Value = 'ok'; Context = 'System'
                Credential = [pscredential]::new('LAB\isl-user', $secure)
            }

            { Invoke-IntuneRequirementTest @requirementSplat } |
                Should-Throw -FullyQualifiedErrorId 'CredentialWithSystemContext,*'
            Should-Invoke Invoke-IslScriptRun -ModuleName IntuneScriptLab -Times 0 -Exactly
        }
    }
}
