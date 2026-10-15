@{
    # Module manifest for IntuneScriptLab
    RootModule = 'IntuneScriptLab.psm1'
    ModuleVersion = '0.33.0'
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
0.33.0 - The CI pieces, after a run against a repository laid out the way the templates describe.
        The gate script no longer analyzes a Pester suite next to the scripts or the contents of a
        Win32 app's Package folder, both of which the suite template puts there and both of which
        failed a build at -FailOn Warning for findings that do not apply to them; its GitHub
        annotations percent-encode the file and title values as well as the message.
        Export-IntuneFindingSarif describes the assignment, filter and schedule rules, gives a
        mixed-severity rule the level of its worst finding, and writes a policy check, which has no
        script behind it, as a result without a location instead of throwing. The workflow template
        uses checkout@v7 and upload-sarif@v4; the suite template names its static tests by package
        and runs the device's own 64-bit host, so it works on Windows on ARM. See CHANGELOG.md.
0.32.0 - Get-IntuneAgentTimeline read Kind as Unknown for a policy whose lines all sat in a rolled
        log file (HealthScripts-20260925-101500 lost only its time part); it reads Remediation or
        Win32App like one from the current file. The Policy column of the health report and drift
        tables is 40 characters wide, so a long policy name stays on one line. The README's log
        blocks show the Agent abbreviation and the list form of the diagnostic result. See
        CHANGELOG.md.
0.31.0 - Assignment filter messages. The parser warns about a -contains value that is only
        whitespace, which the service trims to nothing so the clause matches every device; a double
        quote inside a value is refused with a message saying no escape exists and that -contains
        or -startsWith on the parts around it is the way through. In exclude mode,
        Test-IntuneAssignmentFilter and Test-IntuneDeployedScript say what a warning means for the
        assignment: a clause that never matches excludes nobody, so the assignment reaches every
        device in the group. The tenant-wide help example keeps to Windows filters. See
        CHANGELOG.md.
Earlier versions, 0.1.0 to 0.30.0: CHANGELOG.md, which ships with the module.
'@
            RequireLicenseAcceptance = $false
        }
    }
}
