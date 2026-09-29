---
document type: cmdlet
external help file: IntuneScriptLab-Help.xml
HelpUri: https://github.com/fadwen/IntuneScriptLab/blob/main/docs/IntuneScriptLab/Get-IntuneScriptHealth.md
Locale: en-US
Module Name: IntuneScriptLab
ms.date: 09/28/2026
PlatyPS schema version: 2024-05-01
title: Get-IntuneScriptHealth
---

# Get-IntuneScriptHealth

## SYNOPSIS

One line per deployed script policy: findings, drift, assignment and what the devices report.

## SYNTAX

### __AllParameterSets

```
Get-IntuneScriptHealth [[-Kind] <string[]>] [[-Name] <string[]>] [[-Id] <string[]>]
 [[-Path] <string>] [[-Map] <hashtable>] [[-Settings] <Object>] [[-MarkdownPath] <string>]
 [-SkipAnalysis] [-SkipRunState] [-SkipGroupLookup] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Brings the tenant checks together into a health report.
For every remediation, platform script
and Win32 app the tenant has, one object with:

- the analysis findings of Test-IntuneDeployedScript, counted by severity (skip with -SkipAnalysis);
- the drift of Compare-IntuneDeployedScript against a local folder, when -Path is given;
- the assignment: how many include targets, whether any exclusion or filter is on it;
- what the devices reported to Intune (skip with -SkipRunState): a remediation's run summary
  (devices with no issue or remediated, with the issue still detected or back, with a script
  error, pending), a platform script's run summary (succeeded, failed) and an app's install
  counts from the AppInstallStatusAggregate export (installed, failed, pending; one export job
  of about twenty seconds for every app together, because the per-app status endpoints are
  gone from Graph);
- a Health verdict with its reasons: Broken when a finding is an Error, when the policy is
  assigned to nobody, or when every device that ran it failed; Attention when there are
  Warnings, failures, a remediation whose issue stays detected, drift (Drifted, Missing or
  Ambiguous), devices the policy was not applicable to, or an assigned policy that no device
  has reported on yet; Healthy otherwise.

Intune's run states lag the device. A remediation's result travels in the agent's hourly
report batch, not at the run: a fix at 01:37 UTC reached Graph at 02:42 UTC, when the next
cycle uploaded it, and Graph wrote the state within seconds of that upload. A platform script's
run state arrived 2-8 s after the device's log line, an app's install state 30-39 s after
(2026-09-29, Validation\Findings.md). A recurring remediation whose result has not changed is
not re-reported at all, so lastStateUpdateDateTime is the last change, not the last run, and a
count that is days old is not stale.
A policy changed minutes ago is best read with -SkipRunState.
-MarkdownPath writes the same report as a Markdown table per kind, for a wiki or a pull request.
Nothing in the tenant is changed.

## EXAMPLES

### EXAMPLE 1

Connect-MgGraph -Scopes DeviceManagementConfiguration.Read.All, DeviceManagementApps.ReadWrite.All,
    DeviceManagementScripts.Read.All, GroupMember.ReadBasic.All
Get-IntuneScriptHealth | Where-Object Health -ne Healthy

Every policy that needs a look, with the reasons in Notes.

### EXAMPLE 2

Get-IntuneScriptHealth -Path C:\Repos\intune-scripts -MarkdownPath .\intune-health.md

The full report with the drift column, written to a Markdown file as well.

### EXAMPLE 3

Get-IntuneScriptHealth -Kind Remediation -SkipRunState |
    Sort-Object Health | Format-Table Health, PolicyName, Errors, Warnings, Assigned, Notes

The remediations judged on their scripts and assignments alone, without the lagging run states.

### EXAMPLE 4

(Get-IntuneScriptHealth -Name 'Fix-*').Findings | Format-Table RuleName, Role, Message

The findings behind the counts of one policy family.

## PARAMETERS

### -Id

Policy ids to report on, in addition to -Name.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 2
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Kind

Which policy kinds to report on: Remediation, PlatformScript, Win32App.
Default: all three.

```yaml
Type: System.String[]
DefaultValue: "@('Remediation', 'PlatformScript', 'Win32App')"
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

### -Map

Compare-IntuneDeployedScript's -Map: policy name to local file when the layout differs.

```yaml
Type: System.Collections.Hashtable
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 4
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -MarkdownPath

Write the report as Markdown to this file as well, one table per kind, Broken first.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 6
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Name

Policy display names to report on, wildcards allowed.
Default: every policy.

```yaml
Type: System.String[]
DefaultValue: "@('*')"
SupportsWildcards: true
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

### -Path

A folder holding the local copies of the scripts; adds the drift column through
Compare-IntuneDeployedScript (its folder convention, or -Map).

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 3
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Settings

A settings file path or hashtable for the analysis and the settings comparison.

```yaml
Type: System.Object
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 5
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SkipAnalysis

Leave the script rules out: Errors and Warnings are 0 and do not weigh on Health; the assignment check still does.

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

### -SkipGroupLookup

Passed to Test-IntuneDeployedScript: no group member reads.

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

### -SkipRunState

Do not read run summaries or the app install export: the device columns stay empty and do not
weigh on Health.
Faster, and the right choice right after a change.

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

### IntuneScriptLab.HealthReport

One object per policy: Kind, PolicyName, PolicyId, Context (system, user, or the app's install
context), Assigned (include targets, with a note for exclusions and filters), LastModified,
Errors, Warnings, Findings (the objects behind the counts), Drift (InSync, Drifted, Missing, Ambiguous, NotInTenant, NoScript for a policy that carries no script, or empty without -Path) and DriftDetail, Succeeded,
Failed, Detected (remediations: issue detected or back, not fixed), Pending, LastRun,
Health (Healthy, Attention, Broken) and Notes.

## NOTES

Author: Jeffrey Stuhr.
Needs a Microsoft.Graph.Authentication session with DeviceManagementScripts.Read.All
(remediations, platform scripts and their run summaries), DeviceManagementConfiguration.Read.All
(assignment filters), DeviceManagementApps.Read.All (apps) and GroupMember.ReadBasic.All (the
assignment check reads only member ids and types). The app install export creates an export
job, which the Graph reference lists as a write: one of DeviceManagementApps.ReadWrite.All,
DeviceManagementConfiguration.ReadWrite.All or DeviceManagementManagedDevices.ReadWrite.All.
Without it the export is skipped with a warning and the apps' device columns stay empty.

Remediation run states reach Graph with the agent's next hourly report batch (65 minutes after
the run in the 2026-09-29 measurement, seconds after the upload itself); platform script states
2-8 s and Win32 app install states 30-39 s after the device's log line (Validation\Findings.md,
"Reporting latency, re-measured").

## RELATED LINKS

- [Test-IntuneDeployedScript]()
- [Compare-IntuneDeployedScript]()
