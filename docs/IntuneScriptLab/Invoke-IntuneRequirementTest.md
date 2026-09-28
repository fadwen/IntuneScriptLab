---
document type: cmdlet
external help file: IntuneScriptLab-Help.xml
HelpUri: https://github.com/fadwen/IntuneScriptLab/blob/main/docs/IntuneScriptLab/Invoke-IntuneRequirementTest.md
Locale: en-US
Module Name: IntuneScriptLab
ms.date: 09/28/2026
PlatyPS schema version: 2024-05-01
title: Invoke-IntuneRequirementTest
---

# Invoke-IntuneRequirementTest

## SYNOPSIS

Runs a Win32 requirement script like Intune and applies the rule to its output.

## SYNTAX

### __AllParameterSets

```
Invoke-IntuneRequirementTest [-Path] <string> -OutputType <string> -Value <string>
 [-Operator <string>] [-Architecture <string>] [-Context <string>] [-Credential <pscredential>]
 [-TimeoutSeconds <int>]
```

## ALIASES

## DESCRIPTION

Launches the script the way the Intune Management Extension launches a PowerShell
requirement rule (Windows PowerShell 5.1 in the chosen host, -NoProfile -ExecutionPolicy
Bypass -File, working directory C:\WINDOWS\system32, a copy of the script, OEM output) and
evaluates the rule as the agent was observed to: only on exit 0 with nothing on stderr; the
whole console output minus its final line break is the value (Write-Host counts; a second line
or trailing spaces never match); string comparison ignores case; Integer,
Float, Version, Boolean and DateTime outputs are parsed as that type, and an output that
does not parse fails the rule.

Under Intune the requirement runs before the install and after the detection has said
"not installed"; a rule that fails leaves the app "Not applicable".

## EXAMPLES

### EXAMPLE 1

Invoke-IntuneRequirementTest -Path .\Requirement.ps1 -OutputType String -Value 'ok'

Runs the script in the 64-bit host and reports whether the app would be applicable, and
why not if it would not.

### EXAMPLE 2

Invoke-IntuneRequirementTest -Path .\Get-AgentVersion.ps1 -OutputType Version `
    -Operator GreaterThanOrEqual -Value '2.9.0'

A version rule: "2.10.0" meets it, which a string comparison would deny.

### EXAMPLE 3

Invoke-IntuneRequirementTest -Path .\Requirement.ps1 -OutputType Integer -Operator GreaterThan `
    -Value '3' -Context System | Should-BeIntuneApplicable

As SYSTEM from an elevated session, inside a Pester test.

## PARAMETERS

### -Architecture

Host to run in: x64 (the default for requirement rules), x86 (the "run as 32-bit"
option), or arm64 on a Windows on ARM device.

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

User (default) or System.
Intune runs a requirement rule as SYSTEM unless "run using the
logged-on credentials" is set; System reproduces that through a one-shot scheduled task
(elevated session required).
User runs it as the account running this command.

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

### -Operator

Equal (default), NotEqual, GreaterThan, GreaterThanOrEqual, LessThan or LessThanOrEqual.
A Boolean rule accepts only Equal and NotEqual.

```yaml
Type: System.String
DefaultValue: Equal
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

### -OutputType

The rule's output data type as selected in the portal: String, DateTime, Integer, Float,
Version or Boolean.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Path

The requirement script.

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

### -Value

The comparison value as typed in the portal.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: true
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

### IntuneScriptLab.RequirementResult

Applicable, Reason, Output (the text the rule compared), ExitCode, StdOut, StdErr, TimedOut, Duration, OutputType, Operator, Value, Architecture, Context, Host and ScriptPath.

## NOTES

Author: Jeffrey Stuhr.
Every rule and verdict is backed by observations recorded in
Validation\Findings.md (documented vs observed Intune behaviour).

SECURITY: the script runs on this machine with this user's rights (or as SYSTEM with -Context
System).
Only run requirement scripts you trust.
PERFORMANCE: one Windows PowerShell process per run; the default timeout is 5 minutes.

## RELATED LINKS

- [Invoke-IntuneDetectionTest]()
- [Invoke-IntuneWin32AppTest]()
- [Should-BeIntuneApplicable]()
