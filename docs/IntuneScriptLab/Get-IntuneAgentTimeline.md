---
document type: cmdlet
external help file: IntuneScriptLab-Help.xml
HelpUri: https://github.com/fadwen/IntuneScriptLab/blob/main/docs/IntuneScriptLab/Get-IntuneAgentTimeline.md
Locale: en-US
Module Name: IntuneScriptLab
ms.date: 09/28/2026
PlatyPS schema version: 2024-05-01
title: Get-IntuneAgentTimeline
---

# Get-IntuneAgentTimeline

## SYNOPSIS

One timeline per policy or app from the agent's logs: the steps it went through and how they ended.

## SYNTAX

### __AllParameterSets

```
Get-IntuneAgentTimeline [[-Path] <string[]>] [-Log <string[]>] [-Id <string[]>] [-After <datetime>]
 [-Before <datetime>] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Reads the agent's logs through Get-IntuneAgentLog, keeps the lines the event table names and
groups them by the policy or app id they carry, so one object tells the story of one
remediation, platform script or Win32 app: when the agent inspected its schedule or
applicability, launched it, what the detection said and what it reported, in order, with the
time between the first and the last step. A line that carries no id (the queue notice, an
install exit code, AgentExecutor's own lines) belongs to no timeline.
Win32 apps are named from the policy list the agent logs; scripts show the id.

Outcome is the last result the agent logged for the id: a remediation's report result (the
Result code of its report line: 3, the detection found no issue; 4, the issue was found and the
remediation ran, whether or not the post-detection then passed, which Graph tells apart as
remediationState success or remediationFailed; 5, the detection script itself failed; matched
against Graph's run states on the lab devices, 2026-09-29), a platform script's
policy result, an app's reported state or relationship report, detection, applicability or
Enrollment Status Page state.
Runs counts the launches
(remediation starts, script policy starts, app executions).
Steps holds every event with its
time, log, event name and detail, and Summary reads them as one line.

Times are the local times the agent wrote.
The logs are opened with shared access, so the
live agent is no obstacle; a copied log folder works with -Path.

## EXAMPLES

### EXAMPLE 1

Get-IntuneAgentTimeline -Log HealthScripts | Format-Table Id, Started, Duration, Runs, Outcome

Every remediation the agent processed, with how long each took and how it ended.

### EXAMPLE 2

(Get-IntuneAgentTimeline -Id bbf7e139-fe9d-4783-80df-627b8e084059).Steps |
    Format-Table Time, Log, Event, Detail

Step by step for one policy.

### EXAMPLE 3

Get-IntuneAgentTimeline -Path .\Logs -After (Get-Date).AddHours(-1) |
    Where-Object Outcome -like 'App*Report*' | Select-Object Name, Outcome, Summary

The apps a copied log folder shows in the last hour, by name, with their reported states.

## PARAMETERS

### -After

Only steps at or after this time.

```yaml
Type: System.DateTime
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

### -Before

Only steps before this time.

```yaml
Type: System.DateTime
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

### -Id

Only the timelines whose own id is one of these. A line that merely mentions the id (a relationship report names two apps) does not add another timeline.

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

### -Log

Which logs to read: Agent, AppWorkload, HealthScripts, AgentExecutor, All.

```yaml
Type: System.String[]
DefaultValue: "@('Agent', 'AppWorkload', 'HealthScripts', 'AgentExecutor')"
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

A log folder or log file, as Get-IntuneAgentLog takes it.
Default: the agent's log folder.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
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

### IntuneScriptLab.AgentTimeline

One object per id: Id, Name (apps, from the policy list the agent logs; otherwise the id), Kind
(Remediation, PlatformScript, Win32App or Unknown), Started, Ended, Duration, Runs, Outcome,
Steps (IntuneScriptLab.AgentTimelineStep: Time, Log, Event, Detail, Message) and Summary.

## NOTES

Author: Jeffrey Stuhr.
AgentExecutor lines carry no policy id, so they are not part of a
timeline; Get-IntuneAgentLog -Log AgentExecutor shows them by time.

## RELATED LINKS

- [Get-IntuneAgentLog]()
