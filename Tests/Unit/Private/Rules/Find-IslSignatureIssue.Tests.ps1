#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    An unsigned Win32 detection script under an enforced signature check never runs: AgentExecutor
    returned exit 1 without a probe record and the app went "not detected" (W32-DET-SIGCHECK).
#>

BeforeAll {
    $script:ModuleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Find-IslSignatureIssue' -Tag 'Unit', 'Private', 'Rule' {

    It 'flags an unsigned Win32 detection script when the check is enforced by parameter' {
        $path = New-TestScript 'Detect-App.ps1' "Write-Output 'installed'`nexit 0"
        $findings = @(Get-RuleFinding $path IslSignatureIssue @{ EnforceSignatureCheck = 'True' })
        $findings.Count | Should-Be 1
        $findings[0].Severity | Should-Be 'Error'
        $findings[0].Message | Should-BeLikeString 'Signature status NotSigned*does not run an unsigned detection*'
        $findings[0].Evidence | Should-BeLikeString '*W32-DET-SIGCHECK*'
    }

    It 'flags it when the directive turns the check on' {
        $body = "# IntuneScriptLab: ScriptType=Win32Detection EnforceSignatureCheck=true`nWrite-Output 'x'`nexit 0"
        $path = New-TestScript 'Detect-Directive.ps1' $body
        @(Get-RuleFinding $path IslSignatureIssue).Count | Should-Be 1
    }

    It 'words the requirement case as assumed rather than observed' {
        $path = New-TestScript 'App-Requirement.ps1' "Write-Output 'ok'"
        $findings = @(Get-RuleFinding $path IslSignatureIssue @{ EnforceSignatureCheck = 'True' })
        $findings.Count | Should-Be 1
        $findings[0].Message | Should-BeLikeString '*requirement script*assumed for requirement rules*'
    }

    It 'is silent without the check, and for scripts that are not Win32 rules' {
        $path = New-TestScript 'Detect-App.ps1' "Write-Output 'installed'`nexit 0"
        @(Get-RuleFinding $path IslSignatureIssue).Count | Should-Be 0
        $remediation = New-TestScript 'Remediations\Detect.ps1' 'exit 1'
        @(Get-RuleFinding $remediation IslSignatureIssue @{ EnforceSignatureCheck = 'True' }).Count |
            Should-Be 0
    }

    It 'is silent on a validly signed script' {
        $path = New-TestScript 'Detect-Signed.ps1' "Write-Output 'installed'`nexit 0"
        Mock Get-AuthenticodeSignature -ModuleName IntuneScriptLab { [pscustomobject]@{ Status = 'Valid' } }
        @(Get-RuleFinding $path IslSignatureIssue @{ EnforceSignatureCheck = 'True' }).Count | Should-Be 0
    }
}
