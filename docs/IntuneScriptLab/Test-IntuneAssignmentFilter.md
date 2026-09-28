---
document type: cmdlet
external help file: IntuneScriptLab-Help.xml
HelpUri: https://github.com/fadwen/IntuneScriptLab/blob/main/docs/IntuneScriptLab/Test-IntuneAssignmentFilter.md
Locale: en-US
Module Name: IntuneScriptLab
ms.date: 09/28/2026
PlatyPS schema version: 2024-05-01
title: Test-IntuneAssignmentFilter
---

# Test-IntuneAssignmentFilter

## SYNOPSIS

Evaluates an assignment filter rule against a device the way the Intune service does.

## SYNTAX

### __AllParameterSets

```
Test-IntuneAssignmentFilter [-Rule] <string> [[-Device] <Object>] [-Mode <string>] [-SyntaxOnly]
 [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

An assignment filter decides whether a policy or app reaches a device before anything runs:
a filtered-out device reports "Filters criteria are not met." and keeps no state for the
app (Validation\Findings.md, W32-FILTER-INCLUDE / W32-FILTER-EXCLUDE).
Getting a rule
wrong is silent, and the portal's Preview devices needs the tenant.
This command parses a
rule the way the service's validateFilter accepts or refuses it, then evaluates it against
this device or a device you describe, with the matching the service's filter evaluator
showed against real devices (Findings.md, "Assignment filter rules"):

- Comparisons are case-insensitive and leading or trailing spaces in a value are ignored.
- -contains is a substring test and -startsWith a prefix test; -in / -notIn take a list
  (or a single string, read as a one-item list).
- and binds tighter than or; parentheses nest and are optional around a clause.
- A property the tenant has no value for behaves as an empty string: -eq $null matches it,
  -ne "x", -notIn and -notContains match it, -contains and -startsWith do not.
- operatingSystemVersion compares numerically, missing parts as 0: 10.0.26100 is below
  10.0.26100.9457, so -ge 10.0.26100 matches and -eq 10.0.26100 does not.
- cpuArchitecture is amd64, x86, arm64 or unknown; deviceTrustType is "Azure AD joined",
  "Azure AD registered", "Hybrid Azure AD joined" or "Unknown"; operatingSystemSKU is the
  SKU name from the filter reference (a 129 is EnterpriseSEval).
A rule that says "x64" or
  "Microsoft Entra joined" is accepted by the service and never matches a Windows device;
  the command warns about it.

Without -Device the values come from this Windows machine (Get-IslFilterDeviceFact: the
computer name, Win32_ComputerSystem, the CurrentVersion registry key, dsregcmd).
Tenant-side
values (enrollmentProfileName, deviceCategory, isTpmAttested) are unknown locally and
evaluate as empty; pass them in -Device when a rule depends on them.

## EXAMPLES

### EXAMPLE 1

$rule = '(device.deviceName -startsWith "LAB-") and (device.cpuArchitecture -eq "arm64")'
Test-IntuneAssignmentFilter -Rule $rule

Applicable : False
Matched    : False
Mode       : Include
Reason     : Not applicable: the rule does not match this device; the portal shows "Filters criteria
             are not met." (W32-FILTER-INCLUDE)
Clauses    : device.deviceName -startsWith "LAB-" [not matched, actual: DESKTOP-P96U0KB]
             device.cpuArchitecture -eq "arm64" [matched, actual: arm64]

The rule against this device; each clause reports what it saw.

### EXAMPLE 2

$device = @{ deviceName = 'LAB-042'; operatingSystemVersion = '10.0.26100.4652' }
$rule = '(device.operatingSystemVersion -lt 10.0.26100.5000)'
Test-IntuneAssignmentFilter -Rule $rule -Device $device -Mode Exclude

Applicable : False
Matched    : True
Reason     : Not applicable: the exclude rule matches this device (W32-FILTER-EXCLUDE)

A described device against an exclude filter: the version compares numerically and the
match excludes the device.

### EXAMPLE 3

Get-MgBetaDeviceManagementAssignmentFilter | Test-IntuneAssignmentFilter -SyntaxOnly |
    Where-Object Warnings | Select-Object Rule, Warnings

Every filter in the tenant whose rule can never match a Windows device (a "x64" architecture,
a "Microsoft Entra joined" trust type), without evaluating anything.

### EXAMPLE 4

$result = Test-IntuneAssignmentFilter -Rule $rule -Device $device
$result.Clauses | Format-Table Property, Operator, Value, Actual, Matched

The per-clause table: the value the rule asked for, the value the device had, and whether
that clause matched.

## PARAMETERS

### -Device

The device to evaluate, as a hashtable or object whose property names are the filter
properties (deviceName, manufacturer, model, osVersion, operatingSystemVersion,
operatingSystemSKU, cpuArchitecture, deviceTrustType, deviceOwnership,
enrollmentProfileName, deviceCategory, isTpmAttested; names are case-insensitive).
A
property left out is treated as empty.
Without it the local device is read.

```yaml
Type: System.Object
DefaultValue: ''
SupportsWildcards: false
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

### -Mode

Include (the default) or Exclude: how the filter is attached to the assignment.
The verdict
is Applicable, which is Matched for an include filter and not Matched for an exclude one.

```yaml
Type: System.String
DefaultValue: Include
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

### -Rule

The rule as the portal's rule syntax editor or the Graph assignmentFilter.rule holds it,
for the Windows 10 and later platform.
Accepts pipeline input, and binds by property name
so assignment filters read from Graph can be piped in.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
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

### -SyntaxOnly

Parse and validate the rule without evaluating it: Matched and Applicable stay $null, the
clauses and warnings are returned.
Works on any platform, since no device is read.

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

### System.String

A rule, or an object with a Rule property such as an assignment filter read from Graph.

## OUTPUTS

### IntuneScriptLab.FilterResult

Rule, Mode, Matched, Applicable, Reason, Clauses (IntuneScriptLab.FilterClause: Property, Operator, Value, Actual, Matched, Text, Position), Warnings and Device (the values used).

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

The syntax and matching rules were taken from the service itself: 114 rules through
validateFilter and 84 through the filter evaluator against two enrolled devices
(Validation\Invoke-FilterProbe.ps1, FLT-* in Findings.md).
The list of properties is the
Windows device set; managed-app filters (app.*) are refused.
deviceOwnership on the local
device is inferred from the join type, as the two lab devices reported it.

TROUBLESHOOTING:
- A rule the portal accepts is refused here: open an issue with the rule; the parser is
  stricter than the docs only where validateFilter was.
- A clause never matches: read Actual on the clause; the local facts for tenant-side
  properties are empty, so pass -Device with the tenant's values.

## RELATED LINKS

- [](https://learn.microsoft.com/en-us/intune/intune-service/fundamentals/filters-device-properties)
- [Test-IntuneDeployedScript]()
- [Test-IntuneWin32Requirement]()
