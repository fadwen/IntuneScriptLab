#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The Intune agent runs scripts with Windows PowerShell 5.1 (PS-PROBE-HOST), so anything that
    only parses or binds on PowerShell 7 fails before the script's first line.
#>

BeforeAll {
    $script:ModuleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Find-IslPowerShell7Syntax' -Tag 'Unit', 'Private', 'Rule' {

    It 'flags the ternary operator as an error' {
        $path = New-TestScript 'Detect-T.ps1' '$x = $true ? 1 : 2; exit 0'
        $findings = @(Get-RuleFinding $path IslPowerShell7Syntax)
        $findings.Count | Should-Be 1
        $findings[0].Severity | Should-Be 'Error'
        $findings[0].RuleName | Should-Be 'IslPowerShell7Syntax'
    }

    It 'flags pipeline chains, null-coalescing and null-conditional' {
        $path = New-TestScript 'Detect-C.ps1' "Get-Item x || exit 1`n`$a = `$b ?? 'd'`n`$c = `${obj}?.Name`nexit 0"
        @(Get-RuleFinding $path IslPowerShell7Syntax).Count | Should-BeGreaterThanOrEqual 3
    }

    It 'flags ForEach-Object -Parallel, #Requires -Version 7 and 7-only parameters' {
        $path = New-TestScript 'Detect-P.ps1' ("#Requires -Version 7.0`n" +
            "1..3 | ForEach-Object -Parallel { `$_ }`n`$j = '{}' | ConvertFrom-Json -AsHashtable`nexit 0")
        $messages = @(Get-RuleFinding $path IslPowerShell7Syntax).Message -join "`n"
        $messages | Should-BeLikeString '*Requires -Version 7*'
        $messages | Should-BeLikeString '*-Parallel*'
        $messages | Should-BeLikeString '*-AsHashtable*'
    }

    It 'cites the parse-error experiment for syntax only, and the run-time ones for what parses' {
        # A parse error stops the script before its first line (REM-PS7-SYNTAX); a missing cmdlet
        # or parameter fails where it stands and the script carries on (round 10)
        $syntax = New-TestScript 'Detect-S.ps1' '$x = $true ? 1 : 2; exit 0'
        @(Get-RuleFinding $syntax IslPowerShell7Syntax).Evidence | Should-All { $_ -like '*(REM-PS7-SYNTAX)' }

        $path = New-TestScript 'Detect-Rt.ps1' ("'{}' | Test-Json`n`$j = '{}' | ConvertFrom-Json -AsHashtable`n" +
            "1..3 | ForEach-Object -Parallel { `$_ }`nexit 0")
        $findings = @(Get-RuleFinding $path IslPowerShell7Syntax)
        $findings.Count | Should-Be 3
        $findings.Evidence | Should-All { $_ -like '*(REM-PS7-CMDLET, REM-PS7-PARAM, REM-PS7-PARALLEL)' }
        $findings.Evidence | Should-All { $_ -notlike '*parse error*' }
        $findings.Message | Should-All { $_ -like '*the call fails with an error and the script carries on*' }

        $requires = New-TestScript 'Detect-Rq.ps1' "#Requires -Version 7.0`nexit 0"
        @(Get-RuleFinding $requires IslPowerShell7Syntax).Evidence | Should-All { $_ -like '*(REM-PS7-REQUIRES)' }
    }

    It 'flags Out-File -Encoding utf8NoBOM, a value Windows PowerShell 5.1 does not have: <Call>' -ForEach @(
        @{ Call = "'x' | Out-File -FilePath C:\Windows\Temp\a.txt -Encoding utf8NoBOM" }
        @{ Call = "'x' | Out-File C:\Windows\Temp\a.txt -Enc:UTF8NOBOM" }
        @{ Call = "Out-File -Encoding 'utf8NoBOM' -InputObject x -FilePath C:\Windows\Temp\a.txt" }
    ) {
        $path = New-TestScript 'Remediate-E.ps1' "$Call`nexit 0"
        $findings = @(Get-RuleFinding $path IslPowerShell7Syntax)
        $findings.Count | Should-Be 1
        $findings[0].Severity | Should-Be 'Error'
        $findings[0].Message |
            Should-BeLikeString 'Out-File -Encoding utf8NoBOM is a PowerShell 7 value*writes nothing*'
        $findings[0].Evidence | Should-BeLikeString '*(REM-PS7-ENCODING)'
    }

    It 'leaves the encodings both hosts have, a computed encoding and Rename-Item alone' {
        $path = New-TestScript 'Remediate-K.ps1' ("'x' | Out-File C:\Windows\Temp\a.txt -Encoding utf8`n" +
            "'x' | Out-File C:\Windows\Temp\b.txt -Encoding `$encoding`n" +
            "'x' | Out-File C:\Windows\Temp\c.txt`n" +
            "Rename-Item -Path C:\Windows\Temp\a.txt -NewName d.txt`nexit 0")
        @(Get-RuleFinding $path IslPowerShell7Syntax).Count | Should-Be 0
    }

    It 'leaves a module the parser cannot find to the dependency rule' {
        $path = New-TestScript 'Detect-U.ps1' "using module NoSuchModuleForIsl`nexit 0"
        @(Get-RuleFinding $path IslPowerShell7Syntax).Count | Should-Be 0
    }

    It 'stays quiet on 5.1-compatible code' {
        $path = New-TestScript 'Detect-Ok.ps1' ("if (Test-Path 'C:\x') { Write-Output 'ok'; exit 0 } " +
            "else { Write-Output 'missing'; exit 1 }")
        @(Get-RuleFinding $path IslPowerShell7Syntax).Count | Should-Be 0
    }
}
