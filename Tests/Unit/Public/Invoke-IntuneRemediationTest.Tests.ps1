#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The remediation status mapping and its warnings, with the process launch mocked. The detect
    mock reports "present" once a marker file exists beside the script and the remediate mock
    creates it, so Fixed, Recurred and Failed each come from the same flow Intune runs. Real
    launches are covered in Tests\Integration.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-IntuneRemediationTest' -Tag 'Unit', 'Public' {

    BeforeEach {
        # TestDrive lives for the whole file, so each test gets its own folder for the marker
        $case = [guid]::NewGuid().ToString('N')
        $script:Detect = New-TestScript "$case\Detect.ps1" '# real content is irrelevant; the launch is mocked'
        $script:Remediate = New-TestScript "$case\Remediate.ps1" '# mocked'
        $script:Marker = Join-Path (Split-Path $script:Detect -Parent) 'fixed.marker'
        # Detection passes only once the remediation has left its marker
        Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab -ParameterFilter { $Phase -eq 'detect' } {
            if (Test-Path (Join-Path (Split-Path $Path -Parent) 'fixed.marker')) {
                [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = 'present'; StdErr = '' }
            }
            else {
                [pscustomobject]@{ ExitCode = 1; TimedOut = $false; StdOut = 'missing'; StdErr = '' }
            }
        }
        Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab -ParameterFilter { $Phase -eq 'remediate' } {
            $null = New-Item -ItemType File -Path (Join-Path (Split-Path $Path -Parent) 'fixed.marker') -Force
            [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = 'created'; StdErr = '' }
        }
    }

    Context 'Parameter Validation' {
        It 'declares DetectionPath as mandatory and RemediationPath as optional' {
            $command = Get-Command Invoke-IntuneRemediationTest
            $command.Parameters['DetectionPath'].Attributes.Mandatory | Should-ContainCollection $true
            $command.Parameters['RemediationPath'].Attributes.Mandatory | Should-NotContainCollection $true
        }

        It 'defaults to the 32-bit host and the current user, as the portal does' {
            $result = Invoke-IntuneRemediationTest -DetectionPath $script:Detect
            $result.Architecture | Should-Be 'x86'
            $result.Context | Should-Be 'User'
        }

        It 'passes -Credential to every launch and refuses it with Context System' {
            $secure = [securestring]::new()
            foreach ($char in 'pw'.ToCharArray()) { $secure.AppendChar($char) }
            $credential = [pscredential]::new('LAB\isl-user', $secure)
            $remediationSplat = @{
                DetectionPath = $script:Detect; RemediationPath = $script:Remediate; Credential = $credential
            }
            $null = Invoke-IntuneRemediationTest @remediationSplat
            Should-Invoke Invoke-IslScriptRun -ModuleName IntuneScriptLab -Times 2 -ParameterFilter {
                $Credential.UserName -eq 'LAB\isl-user'
            }
            { Invoke-IntuneRemediationTest @remediationSplat -Context System } |
                Should-Throw -ExceptionMessage '*-Credential applies to -Context User*'
        }
    }

    Context 'Core Functionality' {
        It 'reports Fixed when the remediation makes the post-detection pass' {
            $result = Invoke-IntuneRemediationTest -DetectionPath $script:Detect -RemediationPath $script:Remediate
            $result.Status | Should-Be 'Fixed'
            $result.IntuneOutput | Should-Be 'missing'
            $result.RemediationOutput | Should-Be 'created'
            $result.PostOutput | Should-Be 'present'
            $result.PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.RemediationResult'
            Should-Invoke Invoke-IslScriptRun -ModuleName IntuneScriptLab -Exactly -Times 3
        }

        It 'reports Without issues and never runs the remediation when detection exits 0' {
            $null = New-Item -ItemType File -Path $script:Marker
            $result = Invoke-IntuneRemediationTest -DetectionPath $script:Detect -RemediationPath $script:Remediate
            $result.Status | Should-Be 'Without issues'
            $result.Remediation | Should-BeNull
            $result.PostDetection | Should-BeNull
            Should-Invoke Invoke-IslScriptRun -ModuleName IntuneScriptLab -Exactly -Times 0 -ParameterFilter {
                $Phase -eq 'remediate'
            }
        }

        It 'reports Issue detected when there is no remediation script' {
            $result = Invoke-IntuneRemediationTest -DetectionPath $script:Detect
            $result.Status | Should-Be 'Issue detected (no remediation script)'
            $result.Remediation | Should-BeNull
        }

        It 'reports Recurred when the remediation exits 0 but detection still fails' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab -ParameterFilter { $Phase -eq 'remediate' } {
                [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = 'did nothing'; StdErr = '' }
            }
            $result = Invoke-IntuneRemediationTest -DetectionPath $script:Detect -RemediationPath $script:Remediate
            $result.Status | Should-Be 'Recurred'
            $result.PostDetection.ExitCode | Should-Be 1
        }

        It 'reports Failed and skips the post-detection when the remediation exits non-zero' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab -ParameterFilter { $Phase -eq 'remediate' } {
                [pscustomobject]@{ ExitCode = 1; TimedOut = $false; StdOut = ''; StdErr = 'nope' }
            }
            $result = Invoke-IntuneRemediationTest -DetectionPath $script:Detect -RemediationPath $script:Remediate
            $result.Status | Should-Be 'Failed'
            $result.PostDetection | Should-BeNull
        }

        It 'treats any non-zero detection exit as an issue, and warns when it is not 1' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab -ParameterFilter { $Phase -eq 'detect' } {
                [pscustomobject]@{ ExitCode = 2; TimedOut = $false; StdOut = 'still broken'; StdErr = '' }
            }
            $result = Invoke-IntuneRemediationTest -DetectionPath $script:Detect -RemediationPath $script:Remediate
            $result.Status | Should-Be 'Recurred'
            $result.Warnings -join ' ' | Should-BeLikeString '*exited 2*'
        }
    }

    Context 'Output warnings' {
        It 'keeps the last stdout line and the last 2,048 characters, and warns about both' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab -ParameterFilter { $Phase -eq 'detect' } {
                [pscustomobject]@{
                    ExitCode = 0; TimedOut = $false; StdOut = "one`r`ntwo`r`n" + ('x' * 3000); StdErr = ''
                }
            }
            $result = Invoke-IntuneRemediationTest -DetectionPath $script:Detect
            $result.IntuneOutput.Length | Should-Be 2048
            $result.Warnings -join ' ' | Should-BeLikeString '*wrote 3 lines*only the last one*'
            $result.Warnings -join ' ' | Should-BeLikeString '*2,048*'
        }

        It 'warns when stderr is written but the detection still exits 0' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab -ParameterFilter { $Phase -eq 'detect' } {
                [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = 'fine'; StdErr = 'careful' }
            }
            $result = Invoke-IntuneRemediationTest -DetectionPath $script:Detect
            $result.Status | Should-Be 'Without issues'
            $result.IntuneError | Should-Be 'careful'
            $result.Warnings -join ' ' | Should-BeLikeString '*without issues*'
        }

        It 'warns about non-ASCII output, which Intune reports through the OEM code page' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab -ParameterFilter { $Phase -eq 'detect' } {
                [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = 'Gr' + [char]0xFC + [char]0xDF + 'e'
                    StdErr = '' }
            }
            $result = Invoke-IntuneRemediationTest -DetectionPath $script:Detect
            $result.Warnings -join ' ' | Should-BeLikeString '*Non-ASCII*OEM code page*'
        }
    }

    Context 'Error Handling' {
        It 'reports TimedOut when the detection is killed' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab -ParameterFilter { $Phase -eq 'detect' } {
                [pscustomobject]@{ ExitCode = $null; TimedOut = $true; StdOut = ''; StdErr = '' }
            }
            $result = Invoke-IntuneRemediationTest -DetectionPath $script:Detect -RemediationPath $script:Remediate
            $result.Status | Should-Be 'TimedOut'
            $result.Remediation | Should-BeNull
        }

        It 'reports TimedOut when the remediation is killed' {
            Mock Invoke-IslScriptRun -ModuleName IntuneScriptLab -ParameterFilter { $Phase -eq 'remediate' } {
                [pscustomobject]@{ ExitCode = $null; TimedOut = $true; StdOut = ''; StdErr = '' }
            }
            $result = Invoke-IntuneRemediationTest -DetectionPath $script:Detect -RemediationPath $script:Remediate
            $result.Status | Should-Be 'TimedOut'
            $result.PostDetection | Should-BeNull
        }
    }
}
