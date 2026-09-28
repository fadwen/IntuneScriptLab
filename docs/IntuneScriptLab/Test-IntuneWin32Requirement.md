---
document type: cmdlet
external help file: IntuneScriptLab-Help.xml
HelpUri: https://github.com/fadwen/IntuneScriptLab/blob/main/docs/IntuneScriptLab/Test-IntuneWin32Requirement.md
Locale: en-US
Module Name: IntuneScriptLab
ms.date: 09/28/2026
PlatyPS schema version: 2024-05-01
title: Test-IntuneWin32Requirement
---

# Test-IntuneWin32Requirement

## SYNOPSIS

Checks a Win32 app's base requirements against this device the way the Intune agent reports them.

## SYNTAX

### __AllParameterSets

```
Test-IntuneWin32Requirement [[-Architecture] <string[]>] [[-MinimumWindowsRelease] <string>]
 [[-MinimumFreeDiskSpaceMB] <long>] [[-MinimumMemoryMB] <long>] [[-MinimumProcessors] <int>]
 [[-MinimumCpuSpeedMHz] <int>] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Evaluates the Requirements page of a Win32 app (operating system architecture, minimum
operating system, free disk space, memory, logical processors and CPU speed) against the
local device and returns the applicability verdict with the text the portal shows and the
device-side applicability code, from the round-6 experiments (Validation\Findings.md, "Win32
requirements, filters, install context and relationships"):

- architecture: "Device architecture (e.g.
x86/amd64) is not applicable for the
  application." (Applicability 1000)
- free disk space: "Available disk space on the target device is less than the configured
  minimum." (1001)
- memory: "Amount of RAM on the target device is less than the configured minimum." (1003)
- logical processors: "Count of logical processors on the target device is less than the
  configured minimum." (1004)

The minimum operating system and CPU speed checks are evaluated the same way but their
portal text and code were not observed, so the result says so.
Under Intune the detection
script runs once before the applicability verdict, so a not-applicable app still gets one
detection run.

## EXAMPLES

### EXAMPLE 1

Test-IntuneWin32Requirement -Architecture x64 -MinimumWindowsRelease Windows11_23H2

Applicable on a 64-bit Windows 11 24H2 device.

### EXAMPLE 2

Test-IntuneWin32Requirement -Architecture arm64

Not applicable on an x64 device, with the portal's architecture message and code 1000.

### EXAMPLE 3

$r = Test-IntuneWin32Requirement -MinimumFreeDiskSpaceMB 100000000 -MinimumMemoryMB 1000000
PS> $r.Checks | Format-Table Requirement, Met, Actual, Details

Every check with the value read from the device; the first failed check decides the verdict,
as the agent reports one reason.

## PARAMETERS

### -Architecture

The architectures the app allows (x86, x64, arm64), the portal's "Check operating system
architecture".
Leave it out to allow all.

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

### -MinimumCpuSpeedMHz

Minimum CPU speed, in MHz.

```yaml
Type: System.Int32
DefaultValue: 0
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

### -MinimumFreeDiskSpaceMB

Minimum free space on the system drive, in MB.

```yaml
Type: System.Int64
DefaultValue: 0
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

### -MinimumMemoryMB

Minimum physical memory, in MB.

```yaml
Type: System.Int64
DefaultValue: 0
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

### -MinimumProcessors

Minimum number of logical processors.

```yaml
Type: System.Int32
DefaultValue: 0
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

### -MinimumWindowsRelease

The portal's "Minimum operating system", as Graph names it: 1607 to 22H2 for Windows 10,
Windows11_21H2 to Windows11_25H2 for Windows 11.

```yaml
Type: System.String
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### None

This command does not accept pipeline input. Pass the requirements as parameters.

## OUTPUTS

### IntuneScriptLab.ApplicabilityResult

Applicable, Details (the portal text of the first failed check), Applicability (the device-side code: 1000 architecture, 1001 disk space, 1003 memory, 1004 processors; $null where the code was not observed; 0 when applicable), Reason, and Checks: one IntuneScriptLab.RequirementCheck per requirement given, with Requirement, Met, Actual, Expected, Details and Applicability.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

Observed with Intune Management Extension 1.105.152.0 on x64 devices; the architecture check
on an ARM64 device follows the same rule but was not run there.

## RELATED LINKS

- [Add a Win32 app to Microsoft Intune](https://learn.microsoft.com/en-us/intune/app-management/deployment/add-win32)
- [Invoke-IntuneWin32AppTest]()
- [Test-IntuneWin32Rule]()
