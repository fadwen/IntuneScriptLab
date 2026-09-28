---
document type: cmdlet
external help file: IntuneScriptLab-Help.xml
HelpUri: https://github.com/fadwen/IntuneScriptLab/blob/main/docs/IntuneScriptLab/Test-IntuneScript.md
Locale: en-US
Module Name: IntuneScriptLab
ms.date: 09/28/2026
PlatyPS schema version: 2024-05-01
title: Test-IntuneScript
---

# Test-IntuneScript

## SYNOPSIS

Checks a PowerShell script for the mistakes Intune turns into silent failures.

## SYNTAX

### __AllParameterSets

```
Test-IntuneScript [-Path] <string[]> [-ScriptType <string>] [-Context <string>]
 [-Architecture <string>] [-IncludeRule <string[]>] [-ExcludeRule <string[]>]
 [-MinimumSeverity <string>] [-EnforceSignatureCheck] [-Settings <Object>] [-IncludeSuppressed]
 [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Static analysis, no Intune connection and no admin rights needed.
Each rule encodes
behaviour observed on real devices (see Validation\Findings.md), not just the docs:
which exit codes trigger a remediation, what part of the output Intune keeps, how the
32-bit host and the SYSTEM account change paths, what hangs because the agent never
passes -NonInteractive, and what fails to parse under Windows PowerShell 5.1.

The script type, run context and architecture decide which rules apply.
Give them
explicitly, put a directive in the script, or let them be inferred from the file name:

    # IntuneScriptLab: ScriptType=Detection Context=System Architecture=x64

Inference from the file name (whole words): requirement → Win32Requirement; detect with
app/win32/package/software/install/msi/exe → Win32Detection; detect → Detection;
remediate/remediation/fix → Remediation; anything else → PlatformScript.
An
IslAssumedContext note is always emitted when the type was not given explicitly, because
the wrong type silently skips whole rule sets.
Defaults follow the portal: platform
scripts run as the user in 32-bit, remediations as SYSTEM in 32-bit, Win32 detection as
SYSTEM in 64-bit.

Two things in the scripts' own folder shape the run. A Suppress entry in the directive comment
silences a rule (wildcards allowed): in the header before the first statement for the whole
file, on a line of its own for the next line of code, at the end of a line for that line:

    # IntuneScriptLab: ScriptType=Remediation Suppress=IslLongSleep,IslOutput*
    Start-Sleep -Seconds 600   # IntuneScriptLab: Suppress=IslLongSleep

And a file named IntuneScriptLab.settings.psd1 in the scripts' folder or any folder above them
(the nearest wins) carries the exclusions, severity overrides and default type, context,
architecture and signature check a team would otherwise repeat on every call; see -Settings.

## EXAMPLES

### EXAMPLE 1

Test-IntuneScript -Path .\Detect-LegacyTls.ps1 -ScriptType Detection

Runs every rule against a remediation detection script assumed to run as SYSTEM in the
32-bit host.

### EXAMPLE 2

Test-IntuneScript -Path .\Detect-App.ps1 -ScriptType Win32Detection -Architecture x64 |
    Where-Object Severity -eq Error

Only the findings that will make a Win32 detection rule report "not detected".

### EXAMPLE 3

Get-ChildItem .\Remediations -Recurse -Filter *.ps1 | Test-IntuneScript -MinimumSeverity Warning

Analyzes a whole folder, letting each file's name decide its type, and fails a CI step
when anything comes back: `if (Test-IntuneScript ...
) { exit 1 }`.

### EXAMPLE 4

Test-IntuneScript -Path .\Fix-Proxy.ps1 -ExcludeRule IslArchitectureIssue -Context User

A user-context remediation where the 32-bit redirection is handled elsewhere.

### EXAMPLE 5

'x86', 'arm64' | ForEach-Object { Test-IntuneScript -Path .\Detect-Agent.ps1 -Architecture $_ }

A fleet with both x64 and Windows on ARM devices, where the remediation runs in the
default 32-bit host on the former and someone wants to know what changes on the latter.

## PARAMETERS

### -Architecture

The host the script runs in.
x86 (portal default for scripts and remediations), x64
(Win32 detection default), or arm64: the native ARM64 Windows PowerShell that "64-bit"
means on a Windows on ARM device.
ARM64 devices have no x64 PowerShell host; the 32-bit
host there is the emulated x86 one, so x86 findings apply to ARM64 fleets too.
For a mixed
fleet run the analysis once per architecture you deploy to.

```yaml
Type: System.String
DefaultValue: Auto
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

System or User.
Auto (default) uses the directive or the type's portal default.

```yaml
Type: System.String
DefaultValue: Auto
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

Analyze Win32 detection and requirement scripts as if the rule's "Enforce script signature
check" were on: an unsigned script gets an IslSignatureIssue error, because the agent will not
run it. The directive comment "# IntuneScriptLab: EnforceSignatureCheck=true" does the same for
one script.

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

### -ExcludeRule

Skip these rules (wildcards allowed).

```yaml
Type: System.String[]
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

### -IncludeRule

Only run these rules (wildcards allowed), e.g.
'IslExitCodeIssue'.

```yaml
Type: System.String[]
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

### -IncludeSuppressed

Also return the findings a Suppress directive silences, with Suppressed set to true, so a review
can see what was waved through. By default they are dropped.

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

### -MinimumSeverity

Drop findings below this severity.
Information (default) keeps everything.

```yaml
Type: System.String
DefaultValue: Information
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

Script files or folders (searched for *.ps1).
Accepts wildcards and pipeline input.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: true
Aliases:
- FullName
- PSPath
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: true
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: true
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ScriptType

How Intune will run the script.
Auto (default) uses the directive or the file name.

```yaml
Type: System.String
DefaultValue: Auto
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

### -Settings

A settings file path or a hashtable in the file's shape, instead of the search for
IntuneScriptLab.settings.psd1 above each script; @{} means no settings. Keys: ExcludeRule,
IncludeRule, MinimumSeverity, Severity (a hashtable of rule name to severity), ScriptType,
Context, Architecture and EnforceSignatureCheck. Explicit parameters win over the file, and a
script's directive wins over its type, context, architecture and signature entries.

```yaml
Type: System.Object
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### System.String

One or more script or folder paths. A folder is searched recursively for *.ps1.

### System.IO.FileInfo

Get-ChildItem output; the FullName property binds to -Path.

### System.String[]

Several paths at once, bound to -Path.

## OUTPUTS

### IntuneScriptLab.Finding

One object per finding: RuleName, Severity (Information, Warning or Error), Message, ScriptPath, Line, Column, ScriptType, Text (the offending code) and Evidence (the observed Intune behaviour the rule rests on).

## NOTES

Author: Jeffrey Stuhr.
Every rule and verdict is backed by observations recorded in
Validation\Findings.md (documented vs observed Intune behaviour).

PERFORMANCE: static only; a script analyzes in well under a second.
No Intune connection.
SECURITY: reads the file bytes and AST only; nothing is executed.

## RELATED LINKS

- [Invoke-IntuneRemediationTest]()
- [Invoke-IntuneDetectionTest]()
- [Should-PassIntuneAnalysis]()
