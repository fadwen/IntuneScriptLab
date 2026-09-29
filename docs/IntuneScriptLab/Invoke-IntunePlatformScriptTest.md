---
document type: cmdlet
external help file: IntuneScriptLab-Help.xml
HelpUri: https://github.com/fadwen/IntuneScriptLab/blob/main/docs/IntuneScriptLab/Invoke-IntunePlatformScriptTest.md
Locale: en-US
Module Name: IntuneScriptLab
ms.date: 09/28/2026
PlatyPS schema version: 2024-05-01
title: Invoke-IntunePlatformScriptTest
---

# Invoke-IntunePlatformScriptTest

## SYNOPSIS

Runs a platform (device) script the way Intune does and reports its run state.

## SYNTAX

### __AllParameterSets

```
Invoke-IntunePlatformScriptTest [-Path] <string> [-Architecture <string>] [-Context <string>]
 [-Credential <pscredential>] [-TimeoutSeconds <int>] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Same launch as the agent (Windows PowerShell 5.1 in the chosen host, -NoProfile
-ExecutionPolicy Bypass -File, no -NonInteractive, working directory C:\WINDOWS\system32,
copy of the script, OEM output).
Observed reporting for platform scripts: exit 0 is
Success, anything else Failed; unlike remediations the whole output, including
Write-Host, is reported as the result message, so ResultMessage is the full captured text.

The portal's default context for platform scripts is the signed-in user, which is what
User approximates.
-Context System runs it as NT AUTHORITY\SYSTEM in session 0
through a scheduled task (elevated session required).

## EXAMPLES

### EXAMPLE 1

Invoke-IntunePlatformScriptTest -Path .\Configure-Proxy.ps1

Runs the script in the 32-bit host as the current user and reports Success or Failed
with the full output.

### EXAMPLE 2

Invoke-IntunePlatformScriptTest -Path .\Configure-Proxy.ps1 -Architecture x64 -TimeoutSeconds 60

64-bit host with a short timeout.

### EXAMPLE 3

'x86', 'arm64' | ForEach-Object { Invoke-IntunePlatformScriptTest -Path .\Configure.ps1 -Architecture $_ }

Both hosts that exist on a Windows on ARM device.

## PARAMETERS

### -Architecture

x86 (the portal default), x64, or arm64 on a Windows on ARM device.

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

User (default) or System. System runs the script as NT AUTHORITY\SYSTEM in session 0 through a
one-shot scheduled task (elevated session required). User runs it as the account running this
command: Intune runs user-context scripts as the signed-in user, which cannot be impersonated
here, so User reproduces the launch shape and the output rules but not that account's profile or
rights. Intune also skips user-context scripts on Entra-registered devices; only Entra joined and
hybrid-joined devices run them.

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

### -Path

The script.

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
Intune allows 30 minutes; the default here is 5.

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

### IntuneScriptLab.PlatformScriptResult

RunState (Success, Failed or TimedOut), ExitCode, ResultMessage (stdout and stderr as the portal shows them), StdOut, StdErr, TimedOut, Duration, Warnings (on a failure, what Intune does next: three runs in total at policy fetches, then Failed for good), RunAs (the account and logon type the script ran as), Architecture, Context, Host and ScriptPath.

## NOTES

Author: Jeffrey Stuhr.
Every rule and verdict is backed by observations recorded in
Validation\Findings.md (documented vs observed Intune behaviour).

SECURITY: the script really runs on this machine.
Use a test machine or a snapshot.
PERFORMANCE: one Windows PowerShell process per run; the default timeout is 5 minutes.
ENROLLMENT STATUS PAGE: a device-assigned SYSTEM platform script runs in the device setup
phase before the blocking apps and is not tracked by the page, so it cannot rely on anything
those apps install; it runs again, still as SYSTEM, in the first user's script check-in.
User-context scripts run at the start of the account setup phase, before the user's blocking
apps. A user-context script that writes to a file SYSTEM created under ProgramData gets
access denied and is reported Failed despite exit 0 (Findings, "The Enrollment Status Page").

## RELATED LINKS

- [Invoke-IntuneRemediationTest]()
- [Test-IntuneScript]()
- [Should-HaveIntuneRunState]()
