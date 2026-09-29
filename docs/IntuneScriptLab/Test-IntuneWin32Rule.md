---
document type: cmdlet
external help file: IntuneScriptLab-Help.xml
HelpUri: https://github.com/fadwen/IntuneScriptLab/blob/main/docs/IntuneScriptLab/Test-IntuneWin32Rule.md
Locale: en-US
Module Name: IntuneScriptLab
ms.date: 09/28/2026
PlatyPS schema version: 2024-05-01
title: Test-IntuneWin32Rule
---

# Test-IntuneWin32Rule

## SYNOPSIS

Applies a Win32 app file, registry or MSI rule to this device the way the Intune agent does.

## SYNTAX

### File (Default)

```
Test-IntuneWin32Rule -Path <string> -FileOrFolderName <string> -FileOperation <string>
 [-Operator <string>] [-Value <string>] [-Check32BitOn64System] [-RuleType <string>]
 [<CommonParameters>]
```

### Registry

```
Test-IntuneWin32Rule -KeyPath <string> -RegistryOperation <string> [-ValueName <string>]
 [-Operator <string>] [-Value <string>] [-Check32BitOn64System] [-RuleType <string>]
```

### ProductCode

```
Test-IntuneWin32Rule -ProductCode <string> [-Operator <string>] [-Value <string>]
 [-RuleType <string>] [<CommonParameters>]
```

### Rule

```
Test-IntuneWin32Rule -Rule <hashtable> [-RuleType <string>]
```

## ALIASES

## DESCRIPTION

Evaluates one detection or requirement rule of the kinds configured in the portal without a
script (file or folder, registry, MSI product code) and reports whether the agent would call
it met, and why.
Every branch reproduces an observation from the validation rounds
(Validation\Findings.md, "Win32 file, registry and MSI rules"):

- File rules expand %VARIABLE% paths in the 64-bit context, or in the 32-bit context with
  -Check32BitOn64System, where %ProgramFiles% is Program Files (x86).
Version compares the
  file version as a version (10.0.26100.x is above 9.0), SizeInMB compares whole MiB rounded
  down, ModifiedDate and CreatedDate compare in UTC.
DoesNotExist is accepted by the Graph
  API but the agent cannot evaluate it as a detection rule: a missing file is "not detected"
  and a present one is an invalid-rule error (0x87D30004), so this command reports it not
  met either way and says so.
- Registry rules read the 64-bit view, or the WOW6432Node view with -Check32BitOn64System.
  Exists and DoesNotExist work on a key (no value name) or a value; String compares
  case-insensitively; Integer parses the value even from a REG_SZ; Version compares as a
  version and falls back to text when either side is not one.
- Product code rules find per-machine 64-bit, per-machine 32-bit and per-user products; a
  version operator compares DisplayVersion as a version.

The result is what Invoke-IntuneWin32AppTest -DetectionRule uses for each rule, where every
rule must be met for the app to count as installed.

## EXAMPLES

### EXAMPLE 1

Test-IntuneWin32Rule -Path '%ProgramFiles%\Vendor' -FileOrFolderName 'app.exe' -FileOperation Exists

Met when C:\Program Files\Vendor\app.exe exists.

### EXAMPLE 2

Test-IntuneWin32Rule -KeyPath 'HKEY_LOCAL_MACHINE\SOFTWARE\Vendor\App' -ValueName Version `
        -RegistryOperation Version -Operator GreaterThanOrEqual -Value '9.0'

Met when the Version value, read from the 64-bit registry view, is 9.0 or higher as a version.

### EXAMPLE 3

$rule = @{ Type = 'ProductCode'; ProductCode = '{FBE4D84C-C935-4F54-B96F-49316CEB5149}' }
Test-IntuneWin32Rule -Rule $rule

Met when the product is installed, in either registry view or per user.

## PARAMETERS

### -Check32BitOn64System

Expand the path in the 32-bit context (file rule) or read the 32-bit registry view
(registry rule) on a 64-bit device.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Registry
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: File
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -FileOperation

File rule: Exists, DoesNotExist, Version, SizeInMB, ModifiedDate or CreatedDate.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: File
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -FileOrFolderName

File rule: the file or folder name inside Path.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: File
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -KeyPath

Registry rule: the key, as the portal writes it (HKEY_LOCAL_MACHINE\SOFTWARE\Vendor\App).

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Registry
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Operator

Equal, NotEqual, GreaterThan, GreaterThanOrEqual, LessThan or LessThanOrEqual.
Not used by
Exists and DoesNotExist; optional for a product code (without it the rule only checks that
the product is installed).

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: ProductCode
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: Registry
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: File
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

File rule: the folder to look in, with %VARIABLE% references allowed.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: File
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ProductCode

MSI rule: the product code GUID.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: ProductCode
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -RegistryOperation

Registry rule: Exists, DoesNotExist, String, Integer or Version.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Registry
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Rule

The rule as a hashtable instead of separate parameters, in the shape of the Graph
win32LobApp*Rule objects: Type or @odata.type, Path, FileOrFolderName, OperationType,
Operator, ComparisonValue, Check32BitOn64System, KeyPath, ValueName, ProductCode,
ProductVersionOperator, ProductVersion.
This is what -DetectionRule takes.

```yaml
Type: System.Collections.Hashtable
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Rule
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -RuleType

Detection (default) or Requirement; recorded in the result and used in the reasons.

```yaml
Type: System.String
DefaultValue: Detection
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

The comparison value as typed in the portal: a version, a whole number of MiB, a date, a
string, or the product version.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: ProductCode
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: Registry
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: File
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ValueName

Registry rule: the value name; leave it out to test the key itself.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Registry
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

This command does not accept pipeline input. Pass the rule as parameters or as a hashtable.

## OUTPUTS

### IntuneScriptLab.RuleResult

Met, Kind (File, Registry or ProductCode), RuleType (Detection or Requirement), Target (the path, key or product code), Operation, Operator, Value, Actual (what was read from the device), Check32BitOn64System and Reason, which says what was read and, where the agent behaves other than documented, names the experiment.

## NOTES

Author: Jeffrey Stuhr
Blog: https://www.techbyjeff.net
LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

Every behaviour is an observation from the tenant experiments named in the reasons, made with
Intune Management Extension 1.105.152.0; the file DoesNotExist behaviour was observed for
detection rules and is assumed for requirement rules.

## RELATED LINKS

- [Add a Win32 app to Microsoft Intune](https://learn.microsoft.com/en-us/intune/app-management/deployment/add-win32)
- [Invoke-IntuneWin32AppTest]()
