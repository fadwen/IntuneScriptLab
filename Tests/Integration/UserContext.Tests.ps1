#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    -Credential for real: a scheduled task registered for another account runs the script as that
    account, in its own session when it has one (the way the agent runs user-context scripts as
    the signed-in user, REM-PROBE-USER64), otherwise in session 0 with a stored-password logon.

    Needs an elevated session and ISL_TEST_CREDENTIAL pointing at a PSCredential exported with
    Export-Clixml by the identity running the tests (Validation\New-IslHarnessUser.ps1 writes one
    on a lab device). Skipped otherwise.
#>

#pester:no-parallel

BeforeDiscovery {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $isAdmin = ([Security.Principal.WindowsPrincipal]$identity).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    $script:Enabled = $isAdmin -and $env:ISL_TEST_CREDENTIAL -and (Test-Path -LiteralPath $env:ISL_TEST_CREDENTIAL)
}

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
    if ($env:ISL_TEST_CREDENTIAL -and (Test-Path -LiteralPath $env:ISL_TEST_CREDENTIAL)) {
        $script:Credential = Import-Clixml -Path $env:ISL_TEST_CREDENTIAL
        $script:Account = ($script:Credential.UserName -split '\\')[-1]
    }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'User context as another account' -Tag 'Integration', 'Runtime', 'Elevated', 'UserContext' `
    -Skip:(-not $script:Enabled) {

    It 'runs the script as the account from system32, in its session when it has one' {
        $path = New-TestScript 'who.ps1' ('"$([Security.Principal.WindowsIdentity]::GetCurrent().Name)|' +
            '$((Get-Process -Id $PID).SessionId)|$((Get-Location).Path)|$([Environment]::UserInteractive)|' +
            '$env:USERPROFILE"') -Bom
        $testSplat = @{
            Path = $path; Architecture = 'x64'; Context = 'User'; Credential = $script:Credential
            TimeoutSeconds = 180
        }
        $result = Invoke-IntunePlatformScriptTest @testSplat
        $result.RunState | Should-Be 'Success' -Because $result.ResultMessage
        $who, $session, $cwd, $interactive, $profile = $result.StdOut.Trim() -split '\|'
        $who | Should-BeLikeString "*\$($script:Account)"
        $cwd | Should-BeLikeString '*\system32'
        $profile | Should-BeLikeString "*\$($script:Account)*"
        $result.RunAs | Should-BeLikeString "$($script:Credential.UserName) (*)"
        if ($result.RunAs -like '*(Interactive)') {
            # The agent's user-context launch: the user's own session, UserInteractive true
            [int]$session | Should-NotBe 0
            $interactive | Should-Be 'True'
        }
        else {
            [int]$session | Should-Be 0
        }
    }

    It 'maps the remediation flow as the account' {
        $markerName = "user-context-$([guid]::NewGuid().ToString('N')).marker"
        $marker = Join-Path $env:ProgramData "IntuneScriptLab\$markerName"
        $detect = New-TestScript 'Detect.ps1' ("if (Test-Path '$marker') { 'present'; exit 0 } " +
            "else { 'missing'; exit 1 }") -Bom
        $remediate = New-TestScript 'Remediate.ps1' ("New-Item -ItemType File -Path '$marker' -Force | " +
            'Out-Null; exit 0') -Bom
        try {
            $remediationSplat = @{
                DetectionPath = $detect; RemediationPath = $remediate; Architecture = 'x64'
                Context = 'User'; Credential = $script:Credential; TimeoutSeconds = 180
            }
            $result = Invoke-IntuneRemediationTest @remediationSplat
            $result.Status | Should-Be 'Fixed' -Because ($result.Remediation.StdErr + $result.IntuneError)
            $result.IntuneOutput | Should-Be 'missing'
            (Get-Acl -LiteralPath $marker).Owner | Should-BeLikeString "*\$($script:Account)"
        }
        finally {
            Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
        }
    }

    It 'refuses the credential with Context System' {
        $path = New-TestScript 'noop.ps1' 'exit 0' -Bom
        { Invoke-IntunePlatformScriptTest -Path $path -Context System -Credential $script:Credential } |
            Should-Throw -ExceptionMessage '*-Credential applies to -Context User*'
    }
}
