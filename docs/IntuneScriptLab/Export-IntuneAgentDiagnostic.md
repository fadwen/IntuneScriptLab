---
document type: cmdlet
external help file: IntuneScriptLab-Help.xml
HelpUri: https://github.com/fadwen/IntuneScriptLab/blob/main/docs/IntuneScriptLab/Export-IntuneAgentDiagnostic.md
Locale: en-US
Module Name: IntuneScriptLab
ms.date: 09/28/2026
PlatyPS schema version: 2024-05-01
title: Export-IntuneAgentDiagnostic
---

# Export-IntuneAgentDiagnostic

## SYNOPSIS

Packs the agent's logs, its registry state and the parsed timelines into one zip for a ticket.

## SYNTAX

### __AllParameterSets

```
Export-IntuneAgentDiagnostic [-Path] <string> [-LogPath <string>] [-SkipRegistry] [-SkipTimeline]
 [-Force] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Collects from this device what the validation rounds needed to explain a script's behaviour and
writes it as one zip file:

- Logs\: every log in the agent's folder (IntuneManagementExtension, AppWorkload,
  HealthScripts, AgentExecutor and the rest, rolled files included), copied with shared
  access so the live agent is no obstacle;
- Registry\: the agent's own state under HKLM\SOFTWARE\Microsoft\IntuneManagementExtension
  (policies, Win32 app states, script reports), the enrollment's FirstSync values, the
  Enrollment Status Page tracking and the Autopilot diagnostics, as text (skip with
  -SkipRegistry);
- Device\: system.txt (Windows build, architecture, PowerShell version, agent version and
  service state, time zone, this module's version) and dsregcmd.txt (the join state);
- Timeline\: events.csv, every log line the event table names, and timelines.csv, one line
  per policy or app from Get-IntuneAgentTimeline (skip with -SkipTimeline);
- Manifest.txt: what the package holds and when it was made.

The registry text and the logs carry user ids, user names and policy ids: treat the zip as
the support data it is.
Nothing on the device is changed.

## EXAMPLES

### EXAMPLE 1

Export-IntuneAgentDiagnostic -Path C:\Temp\intune-diag.zip

The full package from this device.

### EXAMPLE 2

Export-IntuneAgentDiagnostic -Path .\diag -SkipRegistry -Force

Logs, device facts and timelines only, written to diag.zip over an earlier one.

### EXAMPLE 3

Export-IntuneAgentDiagnostic -Path .\copied.zip -LogPath \\server\share\LAB-042\Logs -SkipRegistry

Timelines and logs from a log folder copied off another device; the registry describes this
machine, so it is left out. The Device section still describes this machine, not the one the
logs came from.

## PARAMETERS

### -Force

Overwrite an existing zip.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
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

### -LogPath

The agent's log folder.
Default: %ProgramData%\Microsoft\IntuneManagementExtension\Logs.

```yaml
Type: System.String
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

The zip file to write.
A .zip extension is added when missing; an existing file is refused
unless -Force is given.

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

### -SkipRegistry

Leave the registry state out.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
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

### -SkipTimeline

Leave the parsed events and timelines out (faster on a large log folder).

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
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

The command takes no pipeline input.

## OUTPUTS

### IntuneScriptLab.Diagnostic

Path (the zip), Files (entries in it), Logs (log files copied), Registry and Timeline (whether
those sections are present) and SizeBytes.

## NOTES

Author: Jeffrey Stuhr.
The registry is read with the caller's rights; a key that cannot be read is left out of the
zip rather than failing the export. dsregcmd /status runs when dsregcmd.exe is on the path.

## RELATED LINKS

- [Get-IntuneAgentLog]()
- [Get-IntuneAgentTimeline]()
