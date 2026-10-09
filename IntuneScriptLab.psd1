@{
    # Module manifest for IntuneScriptLab
    RootModule = 'IntuneScriptLab.psm1'
    ModuleVersion = '0.31.0'
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
0.31.0 - Assignment filter messages. The parser warns about a -contains value that is only
        whitespace, which the service trims to nothing so the clause matches every device; a double
        quote inside a value is refused with a message saying no escape exists and that -contains
        or -startsWith on the parts around it is the way through. In exclude mode,
        Test-IntuneAssignmentFilter and Test-IntuneDeployedScript say what a warning means for the
        assignment: a clause that never matches excludes nobody, so the assignment reaches every
        device in the group. The tenant-wide help example keeps to Windows filters. See
        CHANGELOG.md.
0.30.0 - Invoke-IntuneDetectionTest, Invoke-IntuneRequirementTest and Invoke-IntuneWin32AppTest no
        longer default -Architecture to x64, which Windows on ARM refuses; left out, it is the
        device's 64-bit host (x64, or arm64 on ARM), the one the agent uses. Two Win32 fixes: the
        launcher starts its child without NoDefaultCurrentDirectoryInExePath, a per-user cmd.exe
        setting that made a bare install.cmd fail with "not recognized" although the agent's
        cmd.exe finds it; and the 32-bit host warning also reads the batch file an install or
        uninstall command names, where a powershell.exe call runs 32-bit just the same. See
        CHANGELOG.md.
0.29.0 - A remediation that writes to stderr is a script error on the device whatever its exit code:
        RemediationStatus 3, Graph scriptError, the error text attached, no post-detection.
        Invoke-IntuneRemediationTest reported Recurred for that run since round 1; it reports Failed,
        skips the post-detection and warns that the exit code was 0. A detection's stderr still changes
        nothing. IslOutputIssue warns about Write-Error and an unguarded cmdlet in a remediation script,
        with -ErrorAction Stop as the fix. Measured in user context on the lab device with five one-off
        remediations, recorded as round 11 (REM-STDERR-*). See CHANGELOG.md.
Earlier versions, 0.1.0 to 0.28.0: CHANGELOG.md, which ships with the module.
'@
            RequireLicenseAcceptance = $false
        }
    }
}
