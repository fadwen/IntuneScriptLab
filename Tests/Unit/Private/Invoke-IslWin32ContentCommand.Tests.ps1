#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    A Win32 install or uninstall command line run from a copy of the content, with the process
    launch mocked. Real launches are covered in Tests\Integration\Win32AppWorkflow.Tests.ps1.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }

    function script:Invoke-Content {
        param([hashtable]$Parameters)
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

    It 'ends without starting anything when the content folder is not there' {
        $missing = Join-Path $TestDrive 'no-content'

        { Invoke-Content (@{ Phase = 'install'; Content = $missing; CommandLine = 'setup.exe' } + $script:Base) } |
            Should-Throw -FullyQualifiedErrorId 'PathNotFound,*'
        Should-Invoke Invoke-IslProcess -ModuleName IntuneScriptLab -Times 0 -Exactly
    }
}
