#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    What Intune reports of a script's output: for remediations the last console line, host
    streams included (REM-OUT-STREAMS, REM-OUT-HOSTLAST, REM-OUT-WARNLAST); for Win32 detection
    exit 0 plus stdout plus an empty stderr (W32-DET-*).
#>

BeforeAll {
    $script:ModuleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Find-IslOutputIssue' -Tag 'Unit', 'Private', 'Rule' {

    Context 'Remediation detection' {
        It 'notes Write-Host before the summary and multiple Write-Output lines as information' {
            $path = New-TestScript 'Detect-O.ps1' "Write-Host 'a'`nWrite-Output 'b'`nWrite-Output 'c'`nexit 0"
            $findings = @(Get-RuleFinding $path IslOutputIssue)
            @($findings | Where-Object Severity -eq 'Warning').Count | Should-Be 0
            @($findings | Where-Object Severity -eq 'Information').Count | Should-Be 2
        }

        It 'warns when a host-stream call is the last thing written, because Intune reports its text' {
            $path = New-TestScript 'Detect-O2.ps1' "Write-Output 'ok'`nWrite-Warning 'careful'`nexit 0"
            $findings = @(Get-RuleFinding $path IslOutputIssue)
            @($findings | Where-Object Severity -eq 'Warning').Count | Should-Be 1
            $findings[0].Message | Should-BeLikeString '*WARNING: *'
        }

        It 'does not count Write-Verbose without -Verbose, which prints nothing' {
            $path = New-TestScript 'Detect-O3.ps1' "Write-Output 'ok'`nWrite-Verbose 'quiet'`nexit 0"
            @(Get-RuleFinding $path IslOutputIssue | Where-Object Severity -eq 'Warning').Count | Should-Be 0
        }
    }

    Context 'Win32 detection' {
        It 'errors on exit 0 with no stdout' {
            $path = New-TestScript 'app.ps1' ("# IntuneScriptLab: ScriptType=Win32Detection`n" +
                "if (Test-Path 'C:\app.exe') { exit 0 } else { exit 1 }")
            @(Get-RuleFinding $path IslOutputIssue | Where-Object Severity -eq 'Error').Count | Should-Be 1
        }

        It 'errors on Write-Error, accepts Write-Host as stdout' {
            $path = New-TestScript 'app2.ps1' ("# IntuneScriptLab: ScriptType=Win32Detection`n" +
                "Write-Host 'installed'`nWrite-Error 'oops'`nexit 0")
            $findings = @(Get-RuleFinding $path IslOutputIssue)
            @($findings | Where-Object Message -like '*Write-Error*').Count | Should-Be 1
            @($findings | Where-Object Message -like '*Nothing is ever written*').Count | Should-Be 0
        }

        It 'warns on an unguarded Get-Item, whose error output would defeat the detection' {
            $path = New-TestScript 'app3.ps1' ("# IntuneScriptLab: ScriptType=Win32Detection`n" +
                "Get-ItemProperty 'HKLM:\SOFTWARE\X' | Out-Null`nWrite-Output 'installed'`nexit 0")
            $findings = @(Get-RuleFinding $path IslOutputIssue @{ Architecture = 'x64' })
            @($findings | Where-Object Message -like '*-ErrorAction*').Count | Should-Be 1
        }
    }

    Context 'Platform scripts' {
        It 'is silent, because the whole output is reported' {
            $path = New-TestScript 'script.ps1' "Write-Host 'a'`nWrite-Output 'b'`nWrite-Output 'c'"
            @(Get-RuleFinding $path IslOutputIssue).Count | Should-Be 0
        }
    }

    Context 'Win32 requirement' {
        It 'is silent for one Write-Output of a clean value with exit 0' {
            $path = New-TestScript 'App-Requirement.ps1' "Write-Output 'ok'`nexit 0"
            @(Get-RuleFinding $path IslOutputIssue).Count | Should-Be 0
        }

        It 'accepts Write-Host as the value but counts it as a line beside Write-Output (W32-REQ-HOST)' {
            $alone = New-TestScript 'App-Requirement.ps1' "Write-Host 'ok'"
            @(Get-RuleFinding $alone IslOutputIssue).Count | Should-Be 0
            $both = New-TestScript 'Both-Requirement.ps1' "Write-Host 'checking'`nWrite-Output 'ok'"
            @(Get-RuleFinding $both IslOutputIssue | Where-Object Message -like '2 statements write*').Count |
                Should-Be 1
        }

        It 'errors on Write-Error and on no output at all (W32-REQ-STDERR, W32-REQ-NOOUT)' {
            $stderr = New-TestScript 'App-Requirement.ps1' "Write-Output 'ok'`nWrite-Error 'oops'`nexit 0"
            @(Get-RuleFinding $stderr IslOutputIssue | Where-Object Message -like 'Write-Error*').Count |
                Should-Be 1
            $silent = New-TestScript 'Silent-Requirement.ps1' 'exit 0'
            $errors = @(Get-RuleFinding $silent IslOutputIssue | Where-Object Severity -eq 'Error')
            @($errors | Where-Object Message -like 'Nothing is written*').Count | Should-Be 1
        }

        It 'warns on a second output statement and on whitespace in the value (W32-REQ-LASTLINE, TRAIL)' {
            $two = New-TestScript 'App-Requirement.ps1' "Write-Output 'first'`nWrite-Output 'ok'"
            @(Get-RuleFinding $two IslOutputIssue | Where-Object Message -like '2 statements write*').Count |
                Should-Be 1
            $padded = New-TestScript 'Pad-Requirement.ps1' "Write-Output 'ok   '"
            @(Get-RuleFinding $padded IslOutputIssue | Where-Object Message -like '*whitespace*').Count |
                Should-Be 1
        }

        It 'notes a non-zero exit and warns on an unguarded probing cmdlet' {
            $path = New-TestScript 'App-Requirement.ps1' ("`$v = (Get-ItemProperty 'HKLM:\SOFTWARE\X').Version`n" +
                "if (`$v) { Write-Output `$v } else { exit 1 }")
            $findings = @(Get-RuleFinding $path IslOutputIssue)
            $notes = @($findings | Where-Object Severity -eq 'Information')
            @($notes | Where-Object Message -like 'A non-zero exit*').Count | Should-Be 1
            @($findings | Where-Object Message -like 'Get-ItemProperty writes an error record*').Count |
                Should-Be 1
        }
    }
}
