@{
    # Module manifest for IntuneScriptLab
    RootModule = 'IntuneScriptLab.psm1'
    ModuleVersion = '0.27.0'
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
0.25.0 - The first release from the module's own repository, github.com/fadwen/IntuneScriptLab, and
        the first published to the PowerShell Gallery. Nothing any command does has changed: the
        build scripts moved under Build\, the manifest points at the new repository, and releases
        run from a version tag through the repository's release workflow.
0.24.0 - Docs: about_IntuneScriptLab (Get-Help about_IntuneScriptLab) explains the evidence model,
        the script types and every command; docs\Rules.md is generated from the rule files by
        Build-RuleReference.ps1, one row per finding with its evidence and experiment ids, and a
        unit test keeps it current. The validation kit's scripts no longer use backtick line
        continuations.
0.23.0 - Agent logs: Get-IntuneAgentTimeline tells one policy's or app's story from the named log
        lines (steps, duration, launches, last result); Export-IntuneAgentDiagnostic packs the
        logs, the registry state, the device facts and the parsed events and timelines into one
        zip; the event table gains the relationship lines (AppSubgraph, AppSubgraphSkipped,
        AppRelationshipReport, AppDependencyToast, AppNoIntent, AppDownload) and takes the first
        non-empty GUID as the id, so a userless check-in no longer hides the policy id.
0.22.0 - Health report: Get-IntuneScriptHealth puts the findings, the drift, the assignment and
        what the devices reported (remediation and platform script run summaries, app install
        counts from the AppInstallStatusAggregate export) on one line per policy with a Health
        verdict and its reasons, and writes the same as Markdown with -MarkdownPath.
0.21.0 - Assignment sanity (round 9): Test-IntuneDeployedScript warns about a policy with no
        assignment or only exclusions (never resolved by any device), notes a run-once schedule
        whose time has passed (runs once at the fetch on a device that has not run it) and a
        user-context script assigned to devices (skipped on Entra registered devices).
        Validation\Invoke-AssignmentProbe.ps1 creates the round's policies.
0.20.0 - Drift against git: Compare-IntuneDeployedScript compares every script a tenant's
        remediations, platform scripts and Win32 apps carry with its local copy byte for byte
        (found by convention under -Path or named through -Map), reporting the BOM, line endings,
        whitespace and content apart, a directive or settings file against the policy's run-as,
        bitness and signature check, and policies without a local file, ambiguous matches and local
        files the tenant has no script for as states of their own.
0.19.0 - The Enrollment Status Page: Get-IntuneAgentLog names the page's phases, selected apps,
        registrations, tracked install states and completion (ScriptEspPhase, EspPhase,
        EspAppsSelected, EspAppRegistered, EspAppState, EspPhaseComplete, EspComplete,
        EspNontrackedCheckin, UserlessCheckin), from an Autopilot run recorded in Findings; the
        platform-script and remediation help say where each script type runs relative to the
        page. Validation\Get-IslEspEvidence.ps1 collects the evidence from a lab device.
0.18.1 - Verified on the lab device: the interactive task reproduces the agent's user-context
        launch; a stored-password task the scheduler refuses (0x80070569, no "Log on as a batch
        job" right) is reported at once instead of at the timeout.
0.18.0 - Another account: -Credential on the five Invoke-Intune*Test commands runs the script as
        that account through a scheduled task, in the account's own session when it has one (the
        way the agent runs user-context scripts as the signed-in user) or with a stored-password
        logon in session 0 otherwise; results carry RunAs. Validation\New-IslHarnessUser.ps1
        creates the lab account.
0.17.0 - Assignment filters: Test-IntuneAssignmentFilter parses a filter rule the way the service's
        validateFilter accepts and refuses it and evaluates it against this device or a described
        one with the matching the service's filter evaluator showed (case-insensitive, trimmed
        values, and before or, numeric versions, a missing value as empty); Test-IntuneDeployedScript
        reads the filter on every assignment and flags a clause no Windows device can match
        (IslFilterIssue).
0.16.0 - Three rules from a seventh round: IslExecutionPolicyCall (the agent launches with Bypass),
        IslModuleDependency (modules outside the SYSTEM session's in-box list, and gallery
        installs inside a script) and IslScriptSize (the documented 200 KB against what the
        service accepts and refuses).
0.15.0 - Repair-IntuneScript applies the mechanical, behaviour-preserving fixes: a script-scope
        return becomes the exit 0 it implied (with its value written first), a UTF-16 or BOM-less
        non-ASCII file becomes UTF-8 with a BOM, a padded requirement value is trimmed; findings
        carry the edit as Fix, and -WhatIf previews.
0.14.0 - SARIF: Export-IntuneFindingSarif writes findings as a SARIF 2.1.0 log (rule entries from
        the rules' help, relative paths, in-source suppressions) and the CI gate takes -SarifPath;
        the workflow template uploads it to code scanning on request.
0.13.0 - Suppressions and settings: Suppress=Rule in the directive comment silences a rule for
        the file, the next line or its own line (Test-IntuneScript -IncludeSuppressed shows
        them, findings carry Suppressed); IntuneScriptLab.settings.psd1 next to the scripts
        sets exclusions, severity overrides and the default type, context, architecture and
        signature check, below parameters and directives; -Settings on Test-IntuneScript,
        Test-IntuneDeployedScript and the CI gate.
0.12.0 - CI gate: Examples\Invoke-IntuneScriptGate.ps1 runs the analysis for a build with GitHub
        annotations, a job summary and an exit code at a chosen severity, and
        Examples\intune-script-gate.yml is the workflow to copy into a repository of Intune
        scripts.
0.11.0 - Graph pre-flight: Test-IntuneDeployedScript reads the tenant's remediations, platform
        scripts and Win32 apps through the caller's Microsoft.Graph session and runs the rules on
        every script with the policy's own run-as, bitness and signature settings, plus the file
        doesNotExist rule, the user-context app on a device group and the detect-only remediation.
0.10.0 - PSScriptAnalyzer rules: the analysis as custom rules (PSScriptAnalyzer\IntuneScriptLab.Rules.psm1,
        one Measure-Isl* function per rule) for Invoke-ScriptAnalyzer -CustomRulePath, with
        Get-IntuneAnalyzerRulePath for the path; the daily remediation observed over four days and
        the drift of the hourly schedule.
0.9.0 - Get-IntuneAgentLog: the agent's four CMTrace logs as objects, merged in time order, with
        the events the validation rounds identified (policy fetches, remediation schedule, start
        and verdict, Win32 applicability, detection, rule evaluation, install and report,
        AgentExecutor exit codes and output) and filters by log, id, event, level, time and pattern.
0.8.0 - Win32 dependencies and supersedence: -DependsOn and -Supersedes on Invoke-IntuneWin32AppTest
        run the child-first install, the detect-only block and the replace uninstall the way the
        agent was observed to; a detect-only remediation is one created without a remediation
        script, not an assignment setting.
0.7.0 - Win32 base requirements: Test-IntuneWin32Requirement with the observed applicability
        texts and codes; -InstallContext on Invoke-IntuneWin32AppTest; the 8-hour script policy
        cadence; from a round of tenant experiments on requirements, filters, dependencies,
        supersedence and MSI packages.
0.6.0 - Win32 file, registry and MSI rules: Test-IntuneWin32Rule, multi-rule detection and an
        uninstall flow in Invoke-IntuneWin32AppTest, the enforced signature check on detection
        (-EnforceSignatureCheck, IslSignatureIssue), the platform-script retry limit, all from a
        round of tenant experiments; no backtick line continuations.
0.5.0 - Win32 requirement rules: Invoke-IntuneRequirementTest, Should-BeIntuneApplicable,
        Should-NotBeIntuneApplicable and requirement checks in IslOutputIssue, from a round of
        tenant experiments; harness -Context value User (was CurrentUser); folder-aware type
        inference; PlatyPS help.
0.4.0 - Pester 6.2 assertions: Should-HaveIntuneStatus, Should-BeIntuneDetected,
        Should-NotBeIntuneDetected, Should-HaveIntuneRunState, Should-PassIntuneAnalysis;
        test suite template.
0.3.0 - SYSTEM context via scheduled task; Invoke-IntuneWin32AppTest (detect, install, detect).
0.2.0 - Runtime harness (current user) with x86/x64/arm64 host switching.
0.1.0 - Static rules.
'@
            RequireLicenseAcceptance = $false
        }
    }
}
