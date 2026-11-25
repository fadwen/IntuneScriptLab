#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    A Win32 install or uninstall command line run from a copy of the content, with the process
    launch mocked. Real launches are covered in Tests\Integration\Win32AppWorkflow.Tests.ps1.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    function script:Invoke-Content {
        <#
        .SYNOPSIS
            Runs a Win32 command line with Invoke-IslWin32ContentCommand.

        .DESCRIPTION
            Runs Invoke-IslWin32ContentCommand inside the module, where the private function and the
            mock of Invoke-IslProcess apply, with the parameters splatted onto it.

        .PARAMETER Parameters
            The parameters of Invoke-IslWin32ContentCommand, such as Phase, Content, CommandLine,
            Context, TimeoutSeconds and Warning.

        .EXAMPLE
            Invoke-Content ($run + $script:Base)

            Runs the command line of $run with the context, timeout and warning list of the file.

        .INPUTS
            None.

        .OUTPUTS
            IntuneScriptLab.RunResult. The result of the run.
        #>
        [CmdletBinding()]
        [OutputType('IntuneScriptLab.RunResult')]
        param(
            [hashtable]$Parameters
        )

        InModuleScope IntuneScriptLab -Parameters @{ Parameters = $Parameters } {
            Invoke-IslWin32ContentCommand @Parameters
        }
    }
}

Describe 'Invoke-IslWin32ContentCommand' -Tag 'Unit', 'Private' {

    BeforeEach {
        $script:Content = Join-Path $TestDrive "content-$([guid]::NewGuid().ToString('N'))"
        $null = New-Item -ItemType Directory -Path $script:Content
        Set-Content -LiteralPath (Join-Path $script:Content 'setup.exe') -Value 'binary' -Encoding ascii
        $script:Warnings = [System.Collections.Generic.List[string]]::new()
        $script:Seen = @{}
        # Records the launch and whether the copy was there while it ran
        Mock Invoke-IslProcess -ModuleName IntuneScriptLab {
            $script:Seen['Arguments'] = $Arguments
            $script:Seen['Bitness'] = $LauncherBitness
            $script:Seen['WorkFolder'] = $WorkFolder
            $script:Seen['Credential'] = $Credential
            $script:Seen['Copied'] = Test-Path -LiteralPath (Join-Path $WorkingDirectory 'setup.exe')
            [pscustomobject]@{
                ExitCode = 3010; TimedOut = $false; StdOut = 'done'; StdErr = ''; Duration = [timespan]::Zero
            }
        }
        $script:Base = @{ Context = 'User'; TimeoutSeconds = 600; Warning = $script:Warnings }
    }

    It 'runs the command line through the 32-bit cmd.exe on a copy, and removes the copy afterwards' {
        $run = @{ Phase = 'install'; Content = $script:Content; CommandLine = 'setup.exe /q' }
        $result = Invoke-Content ($run + $script:Base)

        $result | Should-HaveType 'IntuneScriptLab.RunResult'
        $result.Phase | Should-Be 'install'
        $result.Command | Should-Be 'setup.exe /q'
        $result.ExitCode | Should-Be 3010
        $script:Seen['Arguments'] | Should-Be '/C "setup.exe /q"'
        $script:Seen['Bitness'] | Should-Be 'x86'
        $script:Seen['Copied'] | Should-BeTrue
        Test-Path -LiteralPath $script:Seen['WorkFolder'] | Should-BeFalse
        $script:Warnings | Should-BeCollection @()
    }

    It 'warns about powershell.exe in the command line' {
        $line = 'powershell.exe -ExecutionPolicy Bypass -File install.ps1'
        $run = @{ Phase = 'install'; Content = $script:Content; CommandLine = $line }
        $null = Invoke-Content ($run + $script:Base)

        $script:Warnings | Should-BeCollection -Count 1
        $script:Warnings[0] | Should-BeLikeString 'powershell.exe in the install command runs the 32-bit host*'
    }

    It 'warns about powershell.exe in a batch file that the command line names' {
        Set-Content -LiteralPath (Join-Path $script:Content 'install.cmd') -Encoding ascii -Value @(
            '@echo off', 'powershell.exe -File install.ps1')
        $run = @{ Phase = 'install'; Content = $script:Content; CommandLine = 'install.cmd' }
        $null = Invoke-Content ($run + $script:Base)

        $script:Warnings | Should-BeCollection -Count 1
        $script:Warnings[0] | Should-BeLikeString 'powershell.exe in install.cmd (line 2)*'
    }

    It 'reads a quoted batch file name with a space in it' {
        Set-Content -LiteralPath (Join-Path $script:Content 'install app.cmd') -Encoding ascii -Value @(
            '@echo off', 'powershell.exe -File install.ps1')
        $run = @{ Phase = 'install'; Content = $script:Content; CommandLine = '"install app.cmd" /q' }
        $null = Invoke-Content ($run + $script:Base)

        $script:Warnings | Should-BeCollection -Count 1
        $script:Warnings[0] | Should-BeLikeString 'powershell.exe in install app.cmd (line 2)*'
    }

    It 'runs the current user without a credential and without granting a folder' {
        Mock Grant-IslFolderAccess -ModuleName IntuneScriptLab { }
        $run = @{ Phase = 'install'; Content = $script:Content; CommandLine = 'setup.exe' }
        $credential = [System.Management.Automation.PSCredential]::Empty
        $null = Invoke-Content ($run + $script:Base + @{ Credential = $credential })

        $script:Seen['Credential'].UserName | Should-BeNull
        $script:Seen['WorkFolder'] | Should-BeLikeString "$([System.IO.Path]::GetTempPath())*"
        Should-Invoke Grant-IslFolderAccess -ModuleName IntuneScriptLab -Times 0 -Exactly
    }

    Context 'as another account' {
        BeforeEach {
            # The copy goes under ProgramData, which the test points at its own drive
            $script:SavedProgramData = $env:ProgramData
            $env:ProgramData = Join-Path $TestDrive "programdata-$([guid]::NewGuid().ToString('N'))"
            Mock Grant-IslFolderAccess -ModuleName IntuneScriptLab { $script:Seen['Granted'] = $Account }
            $script:Account = [System.Management.Automation.PSCredential]::new(
                'LAB\tester', [System.Security.SecureString]::new())
        }

        AfterEach {
            $env:ProgramData = $script:SavedProgramData
        }

        It 'copies the content under ProgramData, grants the account the folder and runs as it' {
            $run = @{ Phase = 'install'; Content = $script:Content; CommandLine = 'setup.exe' }
            $null = Invoke-Content ($run + $script:Base + @{ Credential = $script:Account })

            $runs = Join-Path $env:ProgramData 'IntuneScriptLabRuns'
            $script:Seen['WorkFolder'] | Should-BeLikeString "$runs\*"
            $script:Seen['Granted'] | Should-Be 'LAB\tester'
            $script:Seen['Credential'].UserName | Should-Be 'LAB\tester'
            $script:Seen['Copied'] | Should-BeTrue
            Test-Path -LiteralPath $script:Seen['WorkFolder'] | Should-BeFalse
        }

        It 'ends with the launch''s error when the launch fails, and still removes the copy' {
            Mock Invoke-IslProcess -ModuleName IntuneScriptLab {
                $script:Seen['WorkFolder'] = $WorkFolder
                $record = [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new('The launch failed'), 'ProcessStartFailed',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
                throw $record
            }
            $run = @{ Phase = 'install'; Content = $script:Content; CommandLine = 'setup.exe' }

            { Invoke-Content ($run + $script:Base + @{ Credential = $script:Account }) } |
                Should-Throw -FullyQualifiedErrorId 'ProcessStartFailed*' -ExceptionMessage 'The launch failed'
            Test-Path -LiteralPath $script:Seen['WorkFolder'] | Should-BeFalse
        }
    }

    It 'ends without starting anything when the content folder is not there' {
        $missing = Join-Path $TestDrive 'no-content'

        { Invoke-Content (@{ Phase = 'install'; Content = $missing; CommandLine = 'setup.exe' } + $script:Base) } |
            Should-Throw -FullyQualifiedErrorId 'PathNotFound,*'
        Should-Invoke Invoke-IslProcess -ModuleName IntuneScriptLab -Times 0 -Exactly
    }
}
