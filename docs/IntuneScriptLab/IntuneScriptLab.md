---
document type: module
Help Version: 1.0.0.0
HelpInfoUri: ''
Locale: en-US
Module Guid: 3f6b2c9e-7d41-4a8f-9c2b-5e0d8a1f4b76
Module Name: IntuneScriptLab
ms.date: 09/28/2026
PlatyPS schema version: 2024-05-01
title: IntuneScriptLab Module
---

# IntuneScriptLab Module

## Description

Test Intune scripts before Intune does: static analysis, a runtime harness, Pester assertions

## IntuneScriptLab Cmdlets

### [Assert-BeIntuneApplicable](Assert-BeIntuneApplicable.md)

Asserts a requirement result meets its rule (alias Should-BeIntuneApplicable).

### [Assert-BeIntuneDetected](Assert-BeIntuneDetected.md)

Asserts a Win32 detection result counts as installed (alias Should-BeIntuneDetected).

### [Assert-HaveIntuneRunState](Assert-HaveIntuneRunState.md)

Asserts the RunState of a platform script result (alias Should-HaveIntuneRunState).

### [Assert-HaveIntuneStatus](Assert-HaveIntuneStatus.md)

Asserts a remediation or Win32 result Status (alias Should-HaveIntuneStatus).

### [Assert-NotBeIntuneApplicable](Assert-NotBeIntuneApplicable.md)

Asserts a requirement result fails its rule (alias Should-NotBeIntuneApplicable).

### [Assert-NotBeIntuneDetected](Assert-NotBeIntuneDetected.md)

Asserts a Win32 detection result counts as not installed (alias Should-NotBeIntuneDetected).

### [Assert-PassIntuneAnalysis](Assert-PassIntuneAnalysis.md)

Asserts Test-IntuneScript finds nothing at Warning or above (alias Should-PassIntuneAnalysis).

### [Compare-IntuneDeployedScript](Compare-IntuneDeployedScript.md)

Reports where a tenant's deployed scripts differ from the copies in a folder or repository.

### [Export-IntuneAgentDiagnostic](Export-IntuneAgentDiagnostic.md)

Packs the agent's logs, its registry state and the parsed timelines into one zip for a ticket.

### [Export-IntuneFindingSarif](Export-IntuneFindingSarif.md)

Writes IntuneScriptLab findings as a SARIF 2.1.0 log for code scanning.

### [Get-IntuneAgentLog](Get-IntuneAgentLog.md)

Reads the Intune Management Extension logs as objects, with the events the agent's lines record.

### [Get-IntuneAgentTimeline](Get-IntuneAgentTimeline.md)

One timeline per policy or app from the agent's logs: the steps it went through and how they ended.

### [Get-IntuneAnalyzerRulePath](Get-IntuneAnalyzerRulePath.md)

Returns IntuneScriptLab's PSScriptAnalyzer rule module, for -CustomRulePath.

### [Get-IntuneScriptHealth](Get-IntuneScriptHealth.md)

One line per deployed script policy: findings, drift, assignment and what the devices report.

### [Invoke-IntuneDetectionTest](Invoke-IntuneDetectionTest.md)

Runs a Win32 custom detection script like Intune and returns the verdict.

### [Invoke-IntunePlatformScriptTest](Invoke-IntunePlatformScriptTest.md)

Runs a platform (device) script the way Intune does and reports its run state.

### [Invoke-IntuneRemediationTest](Invoke-IntuneRemediationTest.md)

Runs a detection/remediation pair like Intune and reports the portal status.

### [Invoke-IntuneRequirementTest](Invoke-IntuneRequirementTest.md)

Runs a Win32 requirement script like Intune and applies the rule to its output.

### [Invoke-IntuneWin32AppTest](Invoke-IntuneWin32AppTest.md)

Runs a Win32 app's detect → install → detect flow the way the Intune agent does.

### [Repair-IntuneScript](Repair-IntuneScript.md)

Applies the mechanical fixes for findings that have one, and reports what is left.

### [Test-IntuneAssignmentFilter](Test-IntuneAssignmentFilter.md)

Evaluates an assignment filter rule against a device the way the Intune service does.

### [Test-IntuneDeployedScript](Test-IntuneDeployedScript.md)

Analyzes the scripts a tenant has deployed, with the settings each policy actually carries.

### [Test-IntuneScript](Test-IntuneScript.md)

Checks a PowerShell script for the mistakes Intune turns into silent failures.

### [Test-IntuneWin32Requirement](Test-IntuneWin32Requirement.md)

Checks a Win32 app's base requirements against this device the way the Intune agent reports them.

### [Test-IntuneWin32Rule](Test-IntuneWin32Rule.md)

Applies a Win32 app file, registry or MSI rule to this device the way the Intune agent does.

