#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The launch shape, with the process itself mocked: the observed agent command line
    (-NoProfile -ExecutionPolicy Bypass -File, no -NonInteractive), system32 as the working
    directory, and the script run from a cache copy that is removed afterwards.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
    $script:Script = New-TestScript 'Detect-Thing.ps1' 'exit 0' -Bom

    function Invoke-ScriptRun {
        param([hashtable]$Parameters)
        InModuleScope IntuneScriptLab -Parameters @{ Parameters = $Parameters } { Invoke-IslScriptRun @Parameters }
    }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-IslScriptRun' -Tag 'Unit', 'Private' {

    BeforeEach {
        # Echo the launch back so the test can read it, and record the cache folder
        Mock Invoke-IslProcess -ModuleName IntuneScriptLab {
            [pscustomobject]@{
                ExitCode = 0; TimedOut = $false; StdErr = ''; Duration = [timespan]::FromSeconds(1)
                StdOut = "$FilePath|$Arguments|$WorkingDirectory|$WorkFolder|$Context|$TimeoutSeconds"
            }
        }
    }

    Context 'Parameter Validation' {
        It 'fails on a script that does not exist' {
            { Invoke-ScriptRun @{ Path = (Join-Path $TestDrive 'missing.ps1'); Architecture = 'x86' } } |
                Should-Throw
        }
    }

    Context 'Core Functionality' {
        It 'launches the agent command line from system32 on a copy named after the phase' {
            $result = Invoke-ScriptRun @{ Path = $script:Script; Architecture = 'x86'; Phase = 'detect' }
            $filePath, $arguments, $cwd, $workFolder, $context, $timeout = $result.StdOut -split '\|'
            $filePath | Should-BeLikeString '*\SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
            $arguments |
                Should-BeLikeString '-NoProfile -ExecutionPolicy Bypass -File "*\IntuneScriptLab\*\detect.ps1"'
            $arguments | Should-NotBeLikeString '*NonInteractive*'
            $cwd | Should-BeLikeString '*\System32'
            $context | Should-Be 'User'
            $timeout | Should-Be '300'
            $result.Host | Should-Be $filePath
            $result.ScriptPath | Should-Be $script:Script
            $result.Phase | Should-Be 'detect'
            $result.PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.RunResult'
        }

        It 'throws for a script that does not exist instead of running nothing' {
            $missing = Join-Path $TestDrive 'nowhere.ps1'
            { Invoke-ScriptRun @{ Path = $missing; Architecture = 'x86' } } | Should-Throw
            Should-Invoke Invoke-IslProcess -ModuleName IntuneScriptLab -Times 0 -Exactly
        }

        It 'removes the cache copy after the run' {
            $result = Invoke-ScriptRun @{ Path = $script:Script; Architecture = 'x86' }
            $workFolder = ($result.StdOut -split '\|')[3]
            $workFolder | Should-BeLikeString '*\IntuneScriptLab\*'
            Test-Path $workFolder | Should-BeFalse
        }

        It 'passes context, timeout and working directory through' {
            $result = Invoke-ScriptRun @{
                Path = $script:Script; Architecture = 'x86'; Context = 'System'; TimeoutSeconds = 9
                WorkingDirectory = $TestDrive
            }
            $null, $null, $cwd, $null, $context, $timeout = $result.StdOut -split '\|'
            $cwd | Should-Be $TestDrive
            $context | Should-Be 'System'
            $timeout | Should-Be '9'
            $result.Context | Should-Be 'System'
        }

        It 'copies the run result through unchanged' {
            Mock Invoke-IslProcess -ModuleName IntuneScriptLab {
                [pscustomobject]@{
                    ExitCode = 4; TimedOut = $true; StdOut = 'o'; StdErr = 'e'; Duration = [timespan]::Zero
                }
            }
            $result = Invoke-ScriptRun @{ Path = $script:Script; Architecture = 'x86' }
            $result.ExitCode | Should-Be 4
            $result.TimedOut | Should-BeTrue
            $result.StdOut | Should-Be 'o'
            $result.StdErr | Should-Be 'e'
        }
    }

    Context 'Another account' {
        It 'runs from a ProgramData cache the account is granted, and passes the credential through' {
            Mock Grant-IslFolderAccess -ModuleName IntuneScriptLab { }
            Mock Invoke-IslProcess -ModuleName IntuneScriptLab {
                [pscustomobject]@{
                    ExitCode = 0; TimedOut = $false; StdErr = ''; Duration = [timespan]::Zero
                    StdOut = "$WorkFolder|$($Credential.UserName)|$LogonType"
                    UserName = $Credential.UserName; LogonType = 'Interactive'
                }
            }
            $secure = [securestring]::new()
            foreach ($char in 'pw'.ToCharArray()) { $secure.AppendChar($char) }
            $credential = [pscredential]::new('isl-user', $secure)
            $result = Invoke-ScriptRun @{
                Path = $script:Script; Architecture = 'x86'; Credential = $credential; LogonType = 'Password'
            }
            $workFolder, $user, $logon = $result.StdOut -split '\|'
            $workFolder | Should-BeLikeString (Join-Path $env:ProgramData 'IntuneScriptLab\Runs\*')
            $user | Should-Be 'isl-user'
            $logon | Should-Be 'Password'
            $result.RunAs | Should-Be 'isl-user (Interactive)'
            $result.UserName | Should-Be 'isl-user'
            Should-Invoke Grant-IslFolderAccess -ModuleName IntuneScriptLab -Exactly -Times 1 -ParameterFilter {
                $Account -eq 'isl-user' -and $Path -eq $workFolder
            }
            Test-Path $workFolder | Should-BeFalse
        }

        It 'keeps the current user run direct, with no grant' {
            Mock Grant-IslFolderAccess -ModuleName IntuneScriptLab { }
            $result = Invoke-ScriptRun @{ Path = $script:Script; Architecture = 'x86' }
            $result.RunAs | Should-BeLikeString '* (*)'
            Should-Invoke Grant-IslFolderAccess -ModuleName IntuneScriptLab -Times 0 -Exactly
        }
    }
}
