---
document type: cmdlet
external help file: IntuneScriptLab-Help.xml
HelpUri: https://github.com/fadwen/IntuneScriptLab/blob/main/docs/IntuneScriptLab/Test-IntuneDeployedScript.md
Locale: en-US
Module Name: IntuneScriptLab
ms.date: 09/28/2026
PlatyPS schema version: 2024-05-01
title: Test-IntuneDeployedScript
---

# Test-IntuneDeployedScript

## SYNOPSIS

Analyzes the scripts a tenant has deployed, with the settings each policy actually carries.

## SYNTAX

### __AllParameterSets

```
Test-IntuneDeployedScript [[-Kind] <string[]>] [[-Name] <string[]>] [[-Id] <string[]>]
 [[-IncludeRule] <string[]>] [[-ExcludeRule] <string[]>] [[-MinimumSeverity] <string>]
 [[-Settings] <Object>] [-SkipGroupLookup] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Reads the remediations, platform scripts and Win32 apps from Microsoft Graph and runs the
same rules as Test-IntuneScript on every script they carry (a remediation's detection and
remediation scripts, a platform script, a Win32 app's script detection rules and script
requirement rules), with the script type, run-as account, bitness and signature check
taken from the policy itself rather than inferred.
What a portal author sees as "Run this
script using the logged-on credentials: Yes" or "Run script in 64-bit PowerShell: No" is
what the analysis assumes, so the verdict matches what the agent will do.

On top of the script rules, seven deployment-level checks that the validation rounds
justified (Validation\Findings.md):

    IslDetectionRuleIssue  Error    a file rule with detectionType doesNotExist: the agent does
                                    not evaluate it (missing file: not detected; present file:
                                    "Invalid detection rule", 0x87D30004)
    IslAssignmentIssue     Warning  a Win32 app with install behavior User assigned to All
                                    devices or to a group whose sampled members (the first
                                    twenty) are all devices: never installed ("userless
                                    check-in", Not applicable, code 1011)
    IslDetectOnly          Info     a remediation with no remediation script: the detection
                                    runs alone on its schedule (remediationState skipped)
    IslFilterIssue         Warning  an assignment filter on the policy with an -eq or -in clause
                                    whose value no Windows device reports ("x64" for
                                    cpuArchitecture, "Microsoft Entra joined" for
                                    deviceTrustType): the service accepts the rule and the
                                    filter evaluator matches nothing on that clause, so a rule
                                    made of it reaches nobody as an include and excludes nobody
                                    as an exclude (FLT-V25, FLT-E07, FLT-V27, FLT-F01); the
                                    message says which for the assignment's own mode. The same
                                    value under -ne or -notIn, and a -contains value that is only
                                    whitespace, match every device; those, the deprecated
                                    osVersion, the undocumented isTpmAttested and a rule this
                                    evaluator cannot read are Information.
    IslAssignmentIssue     Warning  a policy with no assignment, or only exclusions: no device
                                    resolves it, so it never runs (ASSIGN-NONE, ASSIGN-EXCLONLY)
    IslAssignmentIssue     Info     a user-context remediation or platform script assigned to
                                    devices: runs on Entra joined and hybrid joined devices only;
                                    an Entra registered device downloads it and skips it
    IslScheduleIssue       Info     a run-once schedule whose time has passed: a device that ran
                                    it will not again, one that fetches the policy now runs it
                                    once at the fetch (ASSIGN-PAST2)

Needs Microsoft.Graph.Authentication connected first (Connect-MgGraph) with
DeviceManagementScripts.Read.All (remediations and platform scripts),
DeviceManagementConfiguration.Read.All (assignment filters), DeviceManagementApps.Read.All (Win32
apps) and, for the assignment check, GroupMember.ReadBasic.All (only member ids and types are
read; GroupMember.Read.All also works). Each is the least privileged permission the Graph
reference lists for that read.
A group lookup or a filter read that fails (a session without the scope, most often) is reported
once, and the rest of the run does without them.

Script content is written to a temporary folder for the analysis, byte for byte as the
tenant stores it, and removed afterwards.
Nothing in the tenant is changed.

## EXAMPLES

### EXAMPLE 1

Connect-MgGraph -Scopes DeviceManagementScripts.Read.All, DeviceManagementConfiguration.Read.All,
    DeviceManagementApps.Read.All, GroupMember.ReadBasic.All
Test-IntuneDeployedScript -MinimumSeverity Warning

Every deployed script with a warning or an error, as the agent will run it.

### EXAMPLE 2

Test-IntuneDeployedScript -Kind Remediation -Name 'Fix-*' |
    Format-Table Severity, RuleName, Role, Line, Message

The remediations named Fix-* only, detection and remediation scripts alike.

### EXAMPLE 3

Test-IntuneDeployedScript -Kind Win32App -SkipGroupLookup |
    Group-Object PolicyName | Sort-Object Count -Descending | Select-Object Count, Name

Which apps collect the most findings, script and policy checks together, without touching
groups.

## PARAMETERS

### -ExcludeRule

Rule names (wildcards allowed) to skip.

```yaml
Type: System.String[]
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

### -Id

Policy or app ids to include, instead of or in addition to -Name.

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

### -IncludeRule

Rule names (wildcards allowed) to run; everything else is skipped.
Applies to the script
rules and the deployment-level checks alike.

```yaml
Type: System.String[]
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

### -Kind

Which policies to read: Remediation, PlatformScript, Win32App.
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

### -MinimumSeverity

Information (default), Warning or Error: the lowest severity to report.

```yaml
Type: System.String
DefaultValue: Information
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

### -Name

Display names to include, wildcards allowed.
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

### -Settings

A settings file path or a hashtable for the analysis of the downloaded scripts (ExcludeRule,
IncludeRule, MinimumSeverity, Severity overrides and the default type, context, architecture and
signature check), the same shape Test-IntuneScript takes. The tenant's scripts have no folder of
their own to carry a settings file, so nothing is searched for.

```yaml
Type: System.Object
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

### -SkipGroupLookup

Do not read group members for the assignment check; useful without GroupMember.Read.All or
in a large tenant.

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

This command does not accept pipeline input. Pass the filters as parameters.

## OUTPUTS

### IntuneScriptLab.DeploymentFinding

One object per finding: Kind (Remediation, PlatformScript, Win32App), PolicyName, PolicyId, Role (detection, remediation, script, requirement, or policy for the deployment-level checks), RuleName, Severity, Message, ScriptType, Line, Column, Text and Evidence (the observed Intune behaviour behind the rule).

## NOTES

Author: Jeffrey Stuhr.
Every rule and verdict is backed by observations recorded in
Validation\Findings.md.
The analysis runs locally on downloaded content; no policy is
modified.

## RELATED LINKS

- [Test-IntuneScript]()
- [Get-IntuneAgentLog]()
