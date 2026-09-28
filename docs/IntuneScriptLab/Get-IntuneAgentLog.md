---
document type: cmdlet
external help file: IntuneScriptLab-Help.xml
HelpUri: ''
Locale: en-US
Module Name: IntuneScriptLab
ms.date: 09/28/2026
PlatyPS schema version: 2024-05-01
title: Get-IntuneAgentLog
---

# Get-IntuneAgentLog

## SYNOPSIS

Reads the Intune Management Extension logs as objects, with the events the agent's lines record.

## SYNTAX

### Read (Default)

```
Get-IntuneAgentLog [[-Path] <string[]>] [-Log <string[]>] [-Id <string[]>] [-EventName <string[]>]
 [-Pattern <string>] [-Level <string[]>] [-After <datetime>] [-Before <datetime>] [-Last <int>]
 [<CommonParameters>]
```

### List

```
Get-IntuneAgentLog -ListEvent [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Parses the agent's CMTrace logs (IntuneManagementExtension, AppWorkload, HealthScripts and
AgentExecutor, rolled files included) into one object per entry, merges them in time order
and names the event each known line records: a script policy fetch and its download count,
a remediation's schedule inspection, start, detection result and report, a Win32 app's
policy fetch, applicability, detection, rule evaluation, install and report, AgentExecutor's
launch, exit code and script output, the Enrollment Status Page's phase, selected apps,
their registration and tracked install states, its completion and the check-in that follows it,
and an app's relationships: the subgraph it is processed in, a skipped subgraph, the report
that names the impacting app with its classification and conflict reason, the dependency
toast, an unassigned child's missing intent and the content download step.
The event table is the set of lines the validation
rounds used as evidence (Validation\Findings.md), so a filtered read answers "what did the
agent do with my script" without grep.

The logs are opened with shared access, so a live agent is no obstacle.
Times are the local
times the agent wrote.
A folder path reads every log in it that -Log selects; a file path
reads that file.

## EXAMPLES

### EXAMPLE 1

Get-IntuneAgentLog -Log HealthScripts -EventName RemediationStart, DetectionResult -Last 10

The last ten remediation launches and detection verdicts on this device.

### EXAMPLE 2

Get-IntuneAgentLog -Id bbf7e139-fe9d-4783-80df-627b8e084059 -After (Get-Date).AddHours(-2) |
    Format-Table Time, Log, Event, Detail, Message

Everything the agent logged about one policy in the last two hours, across all four logs.

### EXAMPLE 3

Get-IntuneAgentLog -Path .\Logs -Log AppWorkload -EventName AppDetection, AppInstallExit, AppReport |
    Group-Object Id | ForEach-Object { $_.Group | Select-Object -Last 3 }

From a copied log folder: the last detection, install exit code and report per app.

## PARAMETERS

### -After

Keeps entries at or after this time.

```yaml
Type: System.DateTime
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Read
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

Keeps entries before this time.

```yaml
Type: System.DateTime
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Read
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -EventName

One or more event names; keeps the entries that record one of them.
Get-IntuneAgentLog
-ListEvent shows the names.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Read
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

One or more policy or app ids; keeps the entries whose message contains one of them.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Read
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Last

Keeps only the most recent N entries after the other filters.

```yaml
Type: System.Int32
DefaultValue: 0
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Read
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Level

Information, Warning or Error; keeps the entries at those levels.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Read
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ListEvent

Lists the event names and the message pattern behind each instead of reading logs.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: List
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Log

Which logs to read from a folder: Agent (IntuneManagementExtension*.log), AppWorkload,
HealthScripts, AgentExecutor, or All for every .log file.
Default: the four named logs.
Ignored for a file path.

```yaml
Type: System.String[]
DefaultValue: "@('Agent', 'AppWorkload', 'HealthScripts', 'AgentExecutor')"
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Read
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

Log files or folders.
Default: the agent's log folder,
%ProgramData%\Microsoft\IntuneManagementExtension\Logs.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Read
  Position: 0
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Pattern

A regular expression the message must match.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Read
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

This command does not accept pipeline input. Pass the paths and filters as parameters.

## OUTPUTS

### IntuneScriptLab.AgentLogEntry

One object per log entry: Time (the local time the agent wrote), Level (Information, Warning or Error), Component, Thread, Event (the name from the event table, or empty for a line the table does not know), Detail (what the event's pattern captured: an exit code, a detection state, a download count), Id (the first policy or app id in the message), Message, Log (the file's base name) and Line. With -ListEvent, one IntuneScriptLab.AgentLogEventDefinition per event with Event and Pattern.

## NOTES

Author: Jeffrey Stuhr.
The event names follow the observations in Validation\Findings.md;
a line the agent writes that is not in the table has no event and passes through unless
-EventName filters it out.

## RELATED LINKS

- [Invoke-IntuneRemediationTest]()
- [Invoke-IntuneWin32AppTest]()
