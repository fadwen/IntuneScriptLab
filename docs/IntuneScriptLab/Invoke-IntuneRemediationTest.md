---
document type: cmdlet
external help file: IntuneScriptLab-Help.xml
HelpUri: ''
Locale: en-US
Module Name: IntuneScriptLab
ms.date: 09/28/2026
PlatyPS schema version: 2024-05-01
title: Invoke-IntuneRemediationTest
---

# Invoke-IntuneRemediationTest

## SYNOPSIS

Runs a detection/remediation pair like Intune and reports the portal status.

## SYNTAX

### __AllParameterSets

```
Invoke-IntuneRemediationTest [-DetectionPath] <string> [[-RemediationPath] <string>]
 [-Architecture <string>] [-Context <string>] [-Credential <pscredential>] [-TimeoutSeconds <int>]
 [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Reproduces the observed remediation flow: run the detection; if it exits non-zero (any
non-zero, not just 1) run the remediation; if the remediation exits 0 run the detection
again.
The status follows what the device recorded:

    Without issues  detection exited 0, remediation skipped
    Fixed           detection non-zero, remediation 0, post-detection 0
    Recurred        detection non-zero, remediation 0, post-detection still non-zero
    Failed          remediation exited non-zero (post-detection skipped)
    TimedOut        a script hit the timeout

Each script is launched as the agent launches it: Windows PowerShell 5.1 in the chosen
host, -NoProfile -ExecutionPolicy Bypass -File, no -NonInteractive, working directory
C:\WINDOWS\system32, run from a copy of the script, output through the OEM code page.
IntuneOutput is what the portal would show: the last stdout line of the pre-detection,
capped at its last 2,048 characters.
Warnings point out output Intune drops.

Remediations run as SYSTEM by default under Intune; -Context System reproduces that with
a scheduled task (elevated session required).
User, the default here, needs no
rights and is right for packages set to run with the signed-in user's credentials.

## EXAMPLES

### EXAMPLE 1

Invoke-IntuneRemediationTest -DetectionPath .\Detect.ps1 -RemediationPath .\Remediate.ps1

Runs the full flow in the 32-bit host and reports Without issues, Fixed, Recurred or Failed.

### EXAMPLE 2

Invoke-IntuneRemediationTest -DetectionPath .\Detect.ps1 -RemediationPath .\Remediate.ps1 -Architecture x64

The same pair with "Run script in 64-bit PowerShell" on.
A Recurred here and Fixed in x86
(or the reverse) usually means one side is hitting WOW6432Node.

### EXAMPLE 3

$r = Invoke-IntuneRemediationTest -DetectionPath .\Detect.ps1
$r.PreDetection.StdOut

Detection only, with the complete captured output rather than the last line Intune keeps.

## PARAMETERS

### -Architecture

x86 (the portal default for remediations), x64, or arm64 on a Windows on ARM device.

```yaml
Type: System.String
DefaultValue: x86
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Context

User (default) or System. System runs the scripts as NT AUTHORITY\SYSTEM in session 0 through a
one-shot scheduled task (elevated session required); this is the portal's default for
remediations. User runs them as the account running this command: Intune runs user-context
remediations as the signed-in user, which cannot be impersonated here, so User reproduces the
launch shape and the output rules but not that account's profile or rights. Intune also skips
user-context remediations on Entra-registered devices.

```yaml
Type: System.String
DefaultValue: User
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Credential

Run as this account instead of the current user, with -Context User: a one-shot scheduled task registered for the account, interactive inside the account's own session when it holds one (the way the agent runs user-context scripts inside the signed-in user's session, REM-PROBE-USER64), otherwise a stored-password logon in session 0; the result's RunAs says which. Needs an elevated session, and is refused with -Context System. Validation\New-IslHarnessUser.ps1 creates a lab account with a stored credential to use here.

```yaml
Type: System.Management.Automation.PSCredential
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -DetectionPath

The detection script.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -RemediationPath

The remediation script.
Omit for a detection-only package.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 1
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -TimeoutSeconds

Per-script timeout.
Intune allows 60 minutes; the default here is 5.

```yaml
Type: System.Int32
DefaultValue: 300
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### None

This command does not accept pipeline input. Pass the scripts with -DetectionPath and -RemediationPath.

## OUTPUTS

### IntuneScriptLab.RemediationResult

Status (Without issues, Issue detected (no remediation script), Fixed, Recurred, Failed or TimedOut), IntuneOutput and IntuneError (the last line of each stream, 2,048-character tail, as the portal reports them), RemediationOutput, PostOutput, the PreDetection, Remediation and PostDetection runs, Warnings, Architecture, Context and Host.

## NOTES

Author: Jeffrey Stuhr.
Every rule and verdict is backed by observations recorded in
Validation\Findings.md (documented vs observed Intune behaviour).

SECURITY: the remediation script really runs and changes this machine, as the current user or
as SYSTEM with -Context System.
Use a test machine or a snapshot.
PERFORMANCE: up to three Windows PowerShell processes per run; default timeout 5 minutes each.
ENROLLMENT STATUS PAGE: remediations do not run during either phase of the page. The agent
fetches them during the account setup phase and the first detection ran three minutes after
the page closed, device and user policies together, so a remediation cannot prepare anything
the page's apps need (Findings, "The Enrollment Status Page").

## RELATED LINKS

- [Invoke-IntunePlatformScriptTest]()
- [Test-IntuneScript]()
- [Should-HaveIntuneStatus]()
