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
