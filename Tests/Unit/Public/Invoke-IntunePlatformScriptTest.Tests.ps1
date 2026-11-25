#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The platform script run state and result message, with the process launch mocked. Real
    launches are covered in Tests\Integration.
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
    $script:Script = 'C:\lab\script.ps1'
}

Describe 'Invoke-IntunePlatformScriptTest' -Tag 'Unit', 'Public' {

    Context 'Parameter Validation' {
        It 'takes script paths from the pipeline, one result each' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab {
                ConvertTo-FakeRunResult @{ ExitCode = 0; TimedOut = $false; StdOut = 'ok'; StdErr = '' }
            }
            $results = @('C:\lab\a.ps1', 'C:\lab\b.ps1' | Invoke-IntunePlatformScriptTest)
            $results.Count | Should-Be 2
            Should-Invoke Invoke-IslScriptRun -ModuleName IntuneScriptLab -Times 2 -Exactly
        }

        It 'takes several script paths as an array, one result each, as from the pipeline' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab {
                ConvertTo-FakeRunResult @{ ExitCode = 0; TimedOut = $false; StdOut = 'ok'; StdErr = '' }
            }
            $results = @(Invoke-IntunePlatformScriptTest -Path 'C:\lab\a.ps1', 'C:\lab\b.ps1')
            $results.Count | Should-Be 2
            Should-Invoke Invoke-IslScriptRun -ModuleName IntuneScriptLab -Times 1 -Exactly -ParameterFilter {
                $Path -eq 'C:\lab\a.ps1'
            }
            Should-Invoke Invoke-IslScriptRun -ModuleName IntuneScriptLab -Times 1 -Exactly -ParameterFilter {
                $Path -eq 'C:\lab\b.ps1'
            }
        }

        It 'defaults to the 32-bit host and the current user, as the portal does' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab {
                ConvertTo-FakeRunResult @{ ExitCode = 0; TimedOut = $false; StdOut = ''; StdErr = '' }
            }
            $result = Invoke-IntunePlatformScriptTest -Path $script:Script
            $result.Architecture | Should-Be 'x86'
            $result.Context | Should-Be 'User'
            Should-Invoke Invoke-IslScriptRun -ModuleName IntuneScriptLab -Exactly -Times 1 -ParameterFilter {
                $Phase -eq 'script' -and $Architecture -eq 'x86'
            }
        }
    }

    Context 'Core Functionality' {
        It 'reports Success on exit 0 with stdout and stderr joined as the result message' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab {
                ConvertTo-FakeRunResult @{
                    ExitCode = 0; TimedOut = $false; StdOut = "out-1`r`nhost-2`r`n"; StdErr = "warn`r`n"
                }
            }
            $result = Invoke-IntunePlatformScriptTest -Path $script:Script
            $result.RunState | Should-Be 'Success'
            $result.ResultMessage | Should-Be "out-1`r`nhost-2`r`nwarn"
            $result.PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.PlatformScriptResult'
        }

        It 'reports Failed on any non-zero exit' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab {
                ConvertTo-FakeRunResult @{ ExitCode = 5; TimedOut = $false; StdOut = ''; StdErr = 'deliberate' }
            }
            $result = Invoke-IntunePlatformScriptTest -Path $script:Script
            $result.RunState | Should-Be 'Failed'
            $result.ExitCode | Should-Be 5
            $result.ResultMessage | Should-Be 'deliberate'
        }

        It 'warns what Intune does with a failure: three runs in total, at policy fetches (PS-FAIL)' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab {
                ConvertTo-FakeRunResult @{ ExitCode = 1; TimedOut = $false; StdOut = ''; StdErr = 'deliberate' }
            }
            $result = Invoke-IntunePlatformScriptTest -Path $script:Script
            @($result.Warnings).Count | Should-Be 1
            $result.Warnings[0] |
                Should-BeLikeString '*start or restart, otherwise every 8 hours*three runs in total*'
        }

        It 'carries no warning on success' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab {
                ConvertTo-FakeRunResult @{ ExitCode = 0; TimedOut = $false; StdOut = 'ok'; StdErr = '' }
            }
            @((Invoke-IntunePlatformScriptTest -Path $script:Script).Warnings).Count | Should-Be 0
        }
    }

    Context 'Error Handling' {
        It 'reports TimedOut when the script is killed' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab {
                ConvertTo-FakeRunResult @{ ExitCode = $null; TimedOut = $true; StdOut = ''; StdErr = '' }
            }
            $result = Invoke-IntunePlatformScriptTest -Path $script:Script -TimeoutSeconds 1
            $result.RunState | Should-Be 'TimedOut'
            $result.TimedOut | Should-BeTrue
            $result.ExitCode | Should-BeNull
        }

        It 'reports a script that cannot be run and goes on with the next one from the pipeline' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab {
                ConvertTo-FakeRunResult @{ ExitCode = 0; TimedOut = $false; StdOut = 'done'; StdErr = '' }
            }
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab -ParameterFilter { $Path -like '*broken*' } {
                throw 'The host could not be started.'
            }

            $output = 'C:\lab\broken.ps1', $script:Script |
                Invoke-IntunePlatformScriptTest -ErrorAction Continue 2>&1
            $errors = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $results = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })

            $errors | Should-BeCollection -Count 1
            $errors[0].Exception.Message | Should-BeLikeString '*host could not be started*'
            $results | Should-BeCollection -Count 1
            $results[0].RunState | Should-Be 'Success'
        }

        It 'ends at the script that cannot be run when the caller asks it to stop' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab { throw 'The host could not be started.' }

            { 'C:\lab\broken.ps1', $script:Script | Invoke-IntunePlatformScriptTest -ErrorAction Stop } |
                Should-Throw -ExceptionMessage '*host could not be started*'
            Should-Invoke Invoke-IslScriptRun -ModuleName IntuneScriptLab -Times 1 -Exactly
        }
    }

    Context 'Another account' {
        It 'passes -Credential to the launcher, reports RunAs, and refuses it with Context System' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab {
                ConvertTo-FakeRunResult @{
                    ExitCode = 0; TimedOut = $false; StdOut = ''; StdErr = ''; RunAs = 'LAB\isl-user (Interactive)'
                }
            }
            $secure = [securestring]::new()
            foreach ($char in 'pw'.ToCharArray()) { $secure.AppendChar($char) }
            $credential = [pscredential]::new('LAB\isl-user', $secure)
            $result = Invoke-IntunePlatformScriptTest -Path $script:Script -Credential $credential
            $result.RunAs | Should-Be 'LAB\isl-user (Interactive)'
            Should-Invoke Invoke-IslScriptRun -ModuleName IntuneScriptLab -Exactly -Times 1 -ParameterFilter {
                $Credential.UserName -eq 'LAB\isl-user'
            }
            { Invoke-IntunePlatformScriptTest -Path $script:Script -Context System -Credential $credential } |
                Should-Throw -FullyQualifiedErrorId 'CredentialWithSystemContext,*'
        }
    }
}
