---
document type: cmdlet
external help file: IntuneScriptLab-Help.xml
HelpUri: https://github.com/fadwen/IntuneScriptLab/blob/main/docs/IntuneScriptLab/Invoke-IntuneDetectionTest.md
Locale: en-US
Module Name: IntuneScriptLab
ms.date: 10/05/2026
PlatyPS schema version: 2024-05-01
title: Invoke-IntuneDetectionTest
---

# Invoke-IntuneDetectionTest

## SYNOPSIS

Runs a Win32 custom detection script like Intune and returns the verdict.

## SYNTAX

### __AllParameterSets

```
Invoke-IntuneDetectionTest [-Path] <string> [-Architecture <string>] [-Context <string>]
 [-Credential <pscredential>] [-TimeoutSeconds <int>] [-EnforceSignatureCheck] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Launches the script in the requested PowerShell host exactly as the Intune Management
Extension does (see Invoke-IntuneRemediationTest for the launch shape) and applies the
observed detection rule: the app counts as installed only when the script exits 0, wrote
something to stdout, and wrote nothing to stderr.
Write-Host counts as stdout;
Write-Warning does not count as stderr; a cmdlet's own error record does.

Detection scripts run as SYSTEM under Intune.
-Context System reproduces that through a
scheduled task (elevated session required); the default User is quicker and needs
no rights, but results that depend on the account (HKCU, user profile paths) differ, which
Test-IntuneScript's IslContextIssue flags statically.

## EXAMPLES

### EXAMPLE 1

Invoke-IntuneDetectionTest -Path .\Detect-App.ps1

Runs the script in the 64-bit host and reports whether Intune would consider the app
installed, and why not if it wouldn't.

### EXAMPLE 2

Invoke-IntuneDetectionTest -Path .\Detect-App.ps1 -Architecture x86 | Select-Object Detected, Reason

The same script with "Run script as 32-bit process" on, which changes what HKLM:\SOFTWARE
and Program Files resolve to.

### EXAMPLE 3

(Invoke-IntuneDetectionTest -Path .\Detect-App.ps1).Detected | Should -BeTrue

Inside a Pester test.

## PARAMETERS

### -Architecture

Host to run in: x64 (Intune's default for Win32 detection), x86 (the "run as 32-bit"
option), or arm64 on a Windows on ARM device. A Windows on ARM device has no x64 host, so the
x64 default is refused there: pass arm64, the host the agent uses on ARM64.

```yaml
Type: System.String
DefaultValue: x64
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

User (default) or System. System runs the script as NT AUTHORITY\SYSTEM in session 0 through a
one-shot scheduled task, exactly where the agent runs it (elevated session required). User runs
it as the account running this command: Intune runs user-context scripts as the signed-in user,
which cannot be impersonated here, so User reproduces the launch shape and the output rules but
not that account's profile or rights.

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

Run as this account instead of the current user, with -Context User: a one-shot scheduled task registered for the account, interactive inside the account's own session when it holds one (the way the agent runs user-context scripts inside the signed-in user's session, REM-PROBE-USER64), otherwise a stored-password logon in session 0, which needs the account to hold the "Log on as a batch job" right (a standard user does not; the scheduler then never starts the task, and the launcher reports that within seconds rather than at the timeout); the result's RunAs says which. Needs an elevated session, and is refused with -Context System. A Microsoft Entra account can be named by its sign-in name (user@domain, with or without AzureAD\ in front) or by the name Windows gives it (AzureAD\Name, the display name without spaces, cut at 20 characters): the launcher asks Windows which account is meant and finds its session by the Windows name. Validation\New-IslHarnessUser.ps1 creates a lab account with a stored credential to use here.

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

### -EnforceSignatureCheck

The rule's "Enforce script signature check". When the script's Authenticode signature is not
Valid the script is not run: the result is not detected with exit code 1 and the signature status
in the reason, which is what AgentExecutor returned for an unsigned script (W32-DET-SIGCHECK).

```yaml
Type: System.Management.Automation.SwitchParameter
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

### -Path

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

### -TimeoutSeconds

Kill the script after this long.
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

This command does not accept pipeline input. Pass the script path with -Path.

## OUTPUTS

### IntuneScriptLab.DetectionResult

Detected, Reason, ExitCode, StdOut, StdErr, TimedOut, Duration, SignatureStatus (filled with -EnforceSignatureCheck, empty otherwise), RunAs (the account and logon type the script ran as), Architecture, Context, Host and ScriptPath. Detected is true only for exit 0 with stdout and no stderr, which is the rule Intune applies.

## NOTES

Author: Jeffrey Stuhr.
Every rule and verdict is backed by observations recorded in
Validation\Findings.md (documented vs observed Intune behaviour).

SECURITY: the script runs on this machine with this user's rights (or as SYSTEM with -Context
System).
Only run detection scripts you trust.
PERFORMANCE: one Windows PowerShell process per run; the default timeout is 5 minutes.

## RELATED LINKS

- [Invoke-IntuneWin32AppTest]()
- [Test-IntuneScript]()
- [Should-BeIntuneDetected]()
