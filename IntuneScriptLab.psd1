@{
    # Module manifest for IntuneScriptLab
    RootModule = 'IntuneScriptLab.psm1'
    ModuleVersion = '0.28.0'
    GUID = '3f6b2c9e-7d41-4a8f-9c2b-5e0d8a1f4b76'
    Author = 'Jeffrey Stuhr'
    CompanyName = ''
    Copyright = '(c) 2026 Jeffrey Stuhr. All rights reserved.'
    # Two lines, within the repository's 115-character limit; the README carries the long form
    Description = @'
Test Intune scripts before Intune does: static rules, a runtime harness, Pester assertions, a Graph
pre-flight over the tenant's deployed scripts and readers for the agent's logs
'@

    # The analyzer itself runs anywhere. The rules describe Windows PowerShell 5.1 behaviour
    # because that is what the Intune Management Extension runs scripts with.
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    RequiredModules = @()
    FormatsToProcess = @('IntuneScriptLab.Format.ps1xml')

    FunctionsToExport = @(
        'Test-IntuneScript',
        'Invoke-IntuneDetectionTest',
        'Invoke-IntuneRemediationTest',
        'Invoke-IntunePlatformScriptTest',
        'Invoke-IntuneWin32AppTest',
        'Invoke-IntuneRequirementTest',
        'Test-IntuneWin32Rule',
        'Test-IntuneWin32Requirement',
        'Get-IntuneAgentLog',
        'Get-IntuneAgentTimeline',
        'Export-IntuneAgentDiagnostic',
        'Get-IntuneAnalyzerRulePath',
        'Test-IntuneDeployedScript',
        'Compare-IntuneDeployedScript',
        'Get-IntuneScriptHealth',
        'Export-IntuneFindingSarif',
        'Repair-IntuneScript',
        'Test-IntuneAssignmentFilter',
        'Assert-HaveIntuneStatus',
        'Assert-BeIntuneDetected',
        'Assert-NotBeIntuneDetected',
        'Assert-HaveIntuneRunState',
        'Assert-PassIntuneAnalysis',
        'Assert-BeIntuneApplicable',
        'Assert-NotBeIntuneApplicable'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @(
        'Should-HaveIntuneStatus',
        'Should-BeIntuneDetected',
        'Should-NotBeIntuneDetected',
        'Should-HaveIntuneRunState',
        'Should-PassIntuneAnalysis',
        'Should-BeIntuneApplicable',
        'Should-NotBeIntuneApplicable'
    )

    PrivateData = @{
        PSData = @{
            Tags = @('Intune', 'Remediation', 'Win32', 'PSScriptAnalyzer', 'Lint', 'Endpoint', 'Pester')
            LicenseUri = 'https://github.com/fadwen/IntuneScriptLab/blob/main/LICENSE'
            ProjectUri = 'https://github.com/fadwen/IntuneScriptLab'
            ReleaseNotes = @'
0.28.0 - Test-IntuneScript analyzes a script about two and a half times faster, with the syntax tree
        walked once and indexed instead of once per rule; Get-IntuneAgentLog reads a large log
        filtered in a fifth of the time. Repair-IntuneScript takes -Context, -Architecture and
        -EnforceSignatureCheck like Test-IntuneScript, and applies eight more edits: -Force on
        Install-Module and its kin, -ErrorAction SilentlyContinue on a probing cmdlet, exit 1 for an
        exit code Intune reads as 1, $env:ProgramW6432, 'ARM64|AMD64', $PSScriptRoot, a
        Get-Credential -Credential call that returns what it was handed, a Set-ExecutionPolicy or
        #Requires -Version 7 line removed. Test-IntuneDeployedScript judges a device group by its
        member counts rather than its first 20 members; every Graph request is retried on 429, 503
        and 504. Invoke-IntuneDetectionTest, Invoke-IntunePlatformScriptTest and
        Invoke-IntuneRequirementTest take script paths from the pipeline; every result type has a
        format view. The in-box module table is held against the host's Windows PowerShell by a
        test, as the PowerShell 7-only tables are. See CHANGELOG.md.
0.27.0 - Harness: a user-context run started from PowerShell 7 gave the 5.1 host PowerShell 7's
        module path (no Cert: drive, Security cmdlets failing to load); -Credential did not find
        a Microsoft Entra account's session, because Windows names such an account after its
        display name and not its sign-in name; a refused folder grant lost its message under
        -ErrorAction Stop on 5.1. Rules, from a tenth validation round: IslPowerShell7Syntax says
        that a 7-only cmdlet, parameter or -Parallel fails where it stands and the script carries
        on, and flags Out-File -Encoding utf8NoBOM, which was listed and never matched;
        IslInteractiveCall warns instead of erring when Get-Credential -Credential is handed
        something that may be a built credential; IslContextIssue's drive-letter finding is
        Information, since the letter cannot say whether it is a mapped drive.
        Repair-IntuneScript no longer turns 'return 1; exit 1' into '1; exit 0; exit 1' with no
        finding left. Help: what Invoke-ScriptAnalyzer -Severity does with the custom rules. See
        CHANGELOG.md.
0.26.0 - Every claim in the README, help, about topic, rule reference and examples was checked
        against the code and by running it, and what did not hold was fixed: -Settings never
        reached the pre-flight or the drift compare; -Id alone selected every policy;
        Repair-IntuneScript -WhatIf on a folder returned nothing; the encoding fix corrupted
        ANSI files; a directive earned the assumed-context note; a settings file's ExcludeRule
        beat an explicit -IncludeRule; Should-PassIntuneAnalysis failed on a pipeline of files;
        SARIF rule levels, outside-root URIs and relative output paths; a missing script path
        returned a result; timeline -Id and relationship reports; case-insensitive drift
        compare; All devices for a user-context app; -SkipAnalysis hiding 'assigned to nobody';
        -ne/-notIn filter values; a bare -Confirm; Stop as a guard; using module and two
        parameters in the PowerShell 7 rule; Win32 scripts in the size rule. Help corrected
        throughout. See CHANGELOG.md.
Earlier versions, 0.1.0 to 0.25.0: CHANGELOG.md, which ships with the module.
'@
            RequireLicenseAcceptance = $false
        }
    }
}
