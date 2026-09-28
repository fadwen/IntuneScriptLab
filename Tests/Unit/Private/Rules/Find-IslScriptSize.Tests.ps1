#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Sizes against the documented 200 KB and the sizes the service refused through the API
    (round 7: 512 KB for a remediation, 680 KB for a platform script).
#>

BeforeAll {
    $script:ModuleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')

    function script:New-SizedScript {
        param([string]$Name, [int]$KB)
        $line = '# ' + ('pad' * 33) + "`n"
        New-TestScript $Name (($line * [int][Math]::Ceiling($KB * 1024 / $line.Length)) + 'exit 0')
    }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Find-IslScriptSize' -Tag 'Unit', 'Private', 'Rule' {

    It 'is silent under 200 KB' {
        @(Get-RuleFinding (New-SizedScript 'Detect-Small.ps1' 150) IslScriptSize).Count | Should-Be 0
    }

    It 'warns over the documented 200 KB and names the size' {
        $findings = @(Get-RuleFinding (New-SizedScript 'Detect-Mid.ps1' 250) IslScriptSize)
        $findings.Count | Should-Be 1
        $findings[0].Severity | Should-Be 'Warning'
        $findings[0].Message | Should-BeLikeString 'The file is 25* KB, over the documented 200 KB limit*'
    }

    It 'errors at the size the service refused, per script type' {
        $remediation = @(Get-RuleFinding (New-SizedScript 'Detect-Huge.ps1' 520) IslScriptSize)
        $remediation[0].Severity | Should-Be 'Error'
        $remediation[0].Message | Should-BeLikeString '*refused a remediation of 512 KB*'
        $platformOk = @(Get-RuleFinding (New-SizedScript 'Configure-Big.ps1' 520) IslScriptSize)
        $platformOk[0].Severity | Should-Be 'Warning'
        $platformBad = @(Get-RuleFinding (New-SizedScript 'Configure-Huge.ps1' 700) IslScriptSize)
        $platformBad[0].Severity | Should-Be 'Error'
        $platformBad[0].Message | Should-BeLikeString '*refused a platform script of 680 KB*'
    }
}
