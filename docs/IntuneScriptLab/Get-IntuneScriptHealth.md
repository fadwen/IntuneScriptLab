---
document type: cmdlet
external help file: IntuneScriptLab-Help.xml
HelpUri: ''
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
  Warnings, failures, a remediation whose issue stays detected, drift, or an assigned policy
  that no device has reported on yet; Healthy otherwise.

Intune's run states lag the device: a remediation's result reached Graph up to an hour after
the device ran it in the validation rounds, platform script and app states within minutes
(Validation\Findings.md).
A policy changed minutes ago is best read with -SkipRunState.
-MarkdownPath writes the same report as a Markdown table per kind, for a wiki or a pull request.
Nothing in the tenant is changed.

## EXAMPLES

### EXAMPLE 1

Connect-MgGraph -Scopes DeviceManagementConfiguration.Read.All, DeviceManagementApps.Read.All,
    DeviceManagementScripts.Read.All, DeviceManagementManagedDevices.Read.All
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

Leave the script rules out: Errors and Warnings stay empty and do not weigh on Health.

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
Errors, Warnings, Findings (the objects behind the counts), Drift and DriftDetail, Succeeded,
Failed, Detected (remediations: issue detected or back, not fixed), Pending, LastRun,
Health (Healthy, Attention, Broken) and Notes.

## NOTES

Author: Jeffrey Stuhr.
Needs a Microsoft.Graph.Authentication session with
DeviceManagementConfiguration.Read.All, DeviceManagementScripts.Read.All,
DeviceManagementApps.Read.All and, for the app install export,
DeviceManagementManagedDevices.Read.All; GroupMember.Read.All for the assignment check.

Remediation run states in Graph lagged the device by up to an hour in the validation rounds;
platform script and Win32 app states appeared within seconds to minutes (Validation\Findings.md,
"Remediation daily schedule and detect-only assignment", "Win32 custom detection scripts").

## RELATED LINKS

- [Test-IntuneDeployedScript]()
- [Compare-IntuneDeployedScript]()
