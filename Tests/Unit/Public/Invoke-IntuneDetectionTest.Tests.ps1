#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The Win32 detection verdict, with the process launch mocked: only exit 0 plus stdout plus an
    empty stderr counts as installed (Win32 findings in Validation\Findings.md). Real launches
    are covered in Tests\Integration.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
    $script:Detect = 'C:\lab\detect.ps1'
    $osArchitecture = "$([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)"
    $script:Native = if ($osArchitecture -eq 'Arm64') { 'arm64' } else { 'x64' }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-IntuneDetectionTest' -Tag 'Unit', 'Public' {

    Context 'Parameter Validation' {
        It 'declares Path as mandatory and limits the architecture and context' {
            $command = Get-Command Invoke-IntuneDetectionTest
            $command.Parameters['Path'].Attributes.Mandatory | Should-ContainCollection $true
            $command.Parameters['Architecture'].Attributes.ValidValues |
                Should-BeCollection @('x86', 'x64', 'arm64')
            $command.Parameters['Context'].Attributes.ValidValues | Should-BeCollection @('User', 'System')
        }

        It 'takes script paths from the pipeline, as Get-ChildItem gives them' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab {
                # The result's ScriptPath comes from the launch, which is mocked here
                [pscustomobject]@{
                    ExitCode = 0; TimedOut = $false; StdOut = 'ok'; StdErr = ''; ScriptPath = $Path
                }
            }
            $one = New-TestScript 'Pipe\Detect-One.ps1' 'exit 0'
            $two = New-TestScript 'Pipe\Detect-Two.ps1' 'exit 0'
            $results = @(Get-ChildItem (Split-Path $one) -Filter *.ps1 | Invoke-IntuneDetectionTest)
            $results.Count | Should-Be 2
            @($results.ScriptPath | Sort-Object) | Should-BeCollection @($one, $two)
            @('a.ps1', 'b.ps1' | Invoke-IntuneDetectionTest).Count | Should-Be 2
        }

        It 'rejects a timeout outside 1..86400' {
            { Invoke-IntuneDetectionTest -Path $script:Detect -TimeoutSeconds 0 } | Should-Throw
        }
    }

    Context 'Core Functionality' {
        It 'is detected with exit 0, stdout and no stderr' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab {
                [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = "installed`r`n"; StdErr = '' }
            }
            $result = Invoke-IntuneDetectionTest -Path $script:Detect
            $result.Detected | Should-BeTrue
            $result.Reason | Should-BeLikeString 'Exit 0 with stdout and no stderr'
            $result.PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.DetectionResult'
        }

        It 'is not detected with exit 0 and nothing on stdout' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab {
                [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = ''; StdErr = '' }
            }
            $result = Invoke-IntuneDetectionTest -Path $script:Detect
            $result.Detected | Should-BeFalse
            $result.Reason | Should-BeLikeString '*Nothing on stdout*'
        }

        It 'is not detected when anything reaches stderr, even with stdout and exit 0' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab {
                [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = 'installed'; StdErr = 'oops' }
            }
            $result = Invoke-IntuneDetectionTest -Path $script:Detect
            $result.Detected | Should-BeFalse
            $result.Reason | Should-BeLikeString '*stderr*'
        }

        It 'is not detected on a non-zero exit and names the code' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab {
                [pscustomobject]@{ ExitCode = 1; TimedOut = $false; StdOut = 'installed'; StdErr = '' }
            }
            $result = Invoke-IntuneDetectionTest -Path $script:Detect
            $result.Detected | Should-BeFalse
            $result.Reason | Should-BeLikeString 'Exit code 1:*'
        }

        It 'passes the architecture, context, phase and timeout through to the launch' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab {
                [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = 'x'; StdErr = '' }
            }
            $result = Invoke-IntuneDetectionTest -Path $script:Detect -Architecture x86 -TimeoutSeconds 7
            Should-Invoke Invoke-IslScriptRun -ModuleName IntuneScriptLab -Exactly -Times 1 -ParameterFilter {
                $Architecture -eq 'x86' -and $Context -eq 'User' -and $Phase -eq 'detect' -and
                $TimeoutSeconds -eq 7
            }
            $result.Architecture | Should-Be 'x86'
            $result.Context | Should-Be 'User'
        }

        It 'defaults to the 64-bit host this device has, the one the agent uses for Win32 detection' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab {
                [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = 'x'; StdErr = '' }
            }
            $result = Invoke-IntuneDetectionTest -Path $script:Detect
            Should-Invoke Invoke-IslScriptRun -ModuleName IntuneScriptLab -Exactly -Times 1 -ParameterFilter {
                $Architecture -in 'x64', 'arm64'
            }
            $result.Architecture | Should-Be $script:Native
        }
    }

    Context 'Enforced signature check (W32-DET-SIGCHECK)' {
        BeforeEach {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab {
                [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = 'installed'; StdErr = '' }
            }
            $script:Unsigned = New-TestScript 'Detect-Unsigned.ps1' 'Write-Output installed; exit 0'
        }

        It 'does not run an unsigned script and reports not detected with exit 1, as AgentExecutor does' {
            $result = Invoke-IntuneDetectionTest -Path $script:Unsigned -EnforceSignatureCheck
            $result.Detected | Should-BeFalse
            $result.ExitCode | Should-Be 1
            $result.SignatureStatus | Should-Be 'NotSigned'
            $result.Reason | Should-BeLikeString 'Signature status NotSigned*does not run the script*'
            Should-Invoke Invoke-IslScriptRun -ModuleName IntuneScriptLab -Exactly -Times 0
        }

        It 'runs a validly signed script normally' {
            Mock Get-AuthenticodeSignature -ModuleName IntuneScriptLab { [pscustomobject]@{ Status = 'Valid' } }
            $result = Invoke-IntuneDetectionTest -Path $script:Unsigned -EnforceSignatureCheck
            $result.Detected | Should-BeTrue
            $result.SignatureStatus | Should-Be 'Valid'
            Should-Invoke Invoke-IslScriptRun -ModuleName IntuneScriptLab -Exactly -Times 1
        }

        It 'ignores the signature without the switch' {
            $result = Invoke-IntuneDetectionTest -Path $script:Unsigned
            $result.Detected | Should-BeTrue
            $result.SignatureStatus | Should-Be ''
        }
    }

    Context 'Error Handling' {
        It 'reports a timeout as not detected with the 60-minute rule as the reason' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab {
                [pscustomobject]@{ ExitCode = $null; TimedOut = $true; StdOut = ''; StdErr = '' }
            }
            $result = Invoke-IntuneDetectionTest -Path $script:Detect -TimeoutSeconds 3
            $result.Detected | Should-BeFalse
            $result.TimedOut | Should-BeTrue
            $result.Reason | Should-BeLikeString 'Timed out after 3 s*60-minute*'
        }

        It 'combines every reason when several apply' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab {
                [pscustomobject]@{ ExitCode = 2; TimedOut = $false; StdOut = ''; StdErr = 'err' }
            }
            $reason = (Invoke-IntuneDetectionTest -Path $script:Detect).Reason
            $reason | Should-BeLikeString '*Exit code 2*Nothing on stdout*stderr*'
        }
    }

    Context 'Another account' {
        It 'passes -Credential to the launcher and refuses it with Context System' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab {
                [pscustomobject]@{
                    ExitCode = 0; TimedOut = $false; StdOut = "installed`r`n"; StdErr = ''
                    RunAs = 'LAB\isl-user (Password)'
                }
            }
            $secure = [securestring]::new()
            foreach ($char in 'pw'.ToCharArray()) { $secure.AppendChar($char) }
            $credential = [pscredential]::new('LAB\isl-user', $secure)
            $result = Invoke-IntuneDetectionTest -Path $script:Detect -Credential $credential
            $result.Detected | Should-BeTrue
            $result.RunAs | Should-Be 'LAB\isl-user (Password)'
            Should-Invoke Invoke-IslScriptRun -ModuleName IntuneScriptLab -Exactly -Times 1 -ParameterFilter {
                $Credential.UserName -eq 'LAB\isl-user'
            }
            { Invoke-IntuneDetectionTest -Path $script:Detect -Context System -Credential $credential } |
                Should-Throw -ExceptionMessage '*-Credential applies to -Context User*'
        }
    }
}
