---
document type: cmdlet
external help file: IntuneScriptLab-Help.xml
HelpUri: https://github.com/fadwen/IntuneScriptLab/blob/main/docs/IntuneScriptLab/Compare-IntuneDeployedScript.md
Locale: en-US
Module Name: IntuneScriptLab
ms.date: 09/28/2026
PlatyPS schema version: 2024-05-01
title: Compare-IntuneDeployedScript
---

# Compare-IntuneDeployedScript

## SYNOPSIS

Reports where a tenant's deployed scripts differ from the copies in a folder or repository.

## SYNTAX

### __AllParameterSets

```
Compare-IntuneDeployedScript [-Path] <string> [-Map <hashtable>] [-Kind <string[]>]
 [-Name <string[]>] [-Id <string[]>] [-Settings <Object>] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Reads the remediations, platform scripts and Win32 apps from Microsoft Graph, finds the local
file for every script they carry and compares the two byte for byte.
The tenant stores exactly
what was uploaded, so a difference in the byte order mark, the line endings or trailing
whitespace is a real difference for the agent (Validation\Findings.md, the encoding rows) and
is reported as such, apart from a difference in content.
Point -Path at a checkout of the
commit that should be deployed and the result is the drift between the tenant and git.

Local files are found by convention under -Path, searched recursively:

    Remediation 'Fix-Widget'     a folder named Fix-Widget holding Detect*.ps1 and Remediat*.ps1
    Platform script 'Set-Proxy'  Set-Proxy.ps1 anywhere, or a folder named Set-Proxy with one .ps1
    Win32 app 'Widget 2.0'       a folder named 'Widget 2.0' holding Detect*.ps1 and Requirement*.ps1

Names are matched without regard to case, with every character other than a letter, a digit,
'.', '_' or '-' taken as an underscore, so the app 'Widget: 2.0' matches a folder named
'Widget_ 2.0' or 'widget__2.0'.
-Map names the files directly when the
layout is different.
A policy with no local file, a local match that is ambiguous and, with
-Map, an entry with no policy are reported as their own states rather than skipped.

When a local script carries a directive (# IntuneScriptLab: Context=User Architecture=x64
EnforceSignatureCheck=true) or a settings file sets those keys, the policy's run-as account,
bitness and signature check are compared with it as well.
Inferred values are never compared.

One result per script role.
State is InSync, Drifted, Missing (no local file), Ambiguous
(more than one local candidate) or NotInTenant (a local file for a role the policy does not
carry, or a -Map entry naming a policy the selection did not include; a local folder for a
policy the tenant does not have is not reported); Differences lists what differs (Content,
LineEndings, Whitespace, Bom, Settings)
and Detail says where.
Nothing in the tenant is changed.

## EXAMPLES

### EXAMPLE 1

Connect-MgGraph -Scopes DeviceManagementConfiguration.Read.All, DeviceManagementApps.Read.All
Compare-IntuneDeployedScript -Path C:\Repos\intune-scripts | Where-Object State -ne InSync

Every deployed script whose local copy differs, is missing or is ambiguous.
In a pipeline
an empty result means the tenant matches the checkout.

### EXAMPLE 2

Compare-IntuneDeployedScript -Path . -Kind Remediation -Name 'Fix-*' |
    Format-Table PolicyName, Role, State, Differences, Detail

The remediations named Fix-* against the current folder, with what differs and where.

### EXAMPLE 3

$map = @{
    'Fix-Widget' = @{ Detection = '.\widget\check.ps1'; Remediation = '.\widget\repair.ps1' }
    'Set-Proxy'  = '.\network\proxy.ps1'
}
Compare-IntuneDeployedScript -Path . -Map $map

Named files instead of the folder convention; any other policy still uses the convention.

### EXAMPLE 4

$drift = Compare-IntuneDeployedScript -Path .\Intune | Where-Object Differences -contains 'Bom'
$drift | Select-Object PolicyName, Role, Detail

Scripts whose byte order mark differs between git and the tenant, the difference that changes
how Windows PowerShell 5.1 reads a non-ASCII character.

## PARAMETERS

### -Id

Policy ids to compare, in addition to -Name.

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

### -Kind

Which policy kinds to compare: Remediation, PlatformScript, Win32App.
Default: all three.

```yaml
Type: System.String[]
DefaultValue: "@('Remediation', 'PlatformScript', 'Win32App')"
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

### -Map

Policy display name (or id) to local file, for layouts the convention does not cover.
A
string value names the script of a platform script, the detection script of a remediation
or a Win32 app; a hashtable value names the roles: @{ Detection = '...'; Remediation = '...' }
for a remediation, @{ Detection = '...'; Requirement = '...' } for a Win32 app,
@{ Script = '...' } for a platform script.
An entry whose policy does not exist is reported
as NotInTenant.

```yaml
Type: System.Collections.Hashtable
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

### -Name

Policy display names to compare, wildcards allowed.
Default: every policy.

```yaml
Type: System.String[]
DefaultValue: "@('*')"
SupportsWildcards: true
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

The folder holding the local scripts, typically the root of a checked-out repository or the
folder under it that holds the Intune scripts.
Searched recursively.

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

### -Settings

A settings file path or a hashtable in the file's shape for the settings comparison, instead
of the nearest IntuneScriptLab.settings.psd1 above each local file.

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

### None

The command takes no pipeline input.

## OUTPUTS

### IntuneScriptLab.DriftResult

One object per script role: Kind, PolicyName, PolicyId, Role (detection, remediation, script,
requirement, or policy for a -Map entry with no policy), State (InSync, Drifted, Missing,
Ambiguous, NotInTenant), Differences (Content, LineEndings, Whitespace, Bom, Settings), Detail,
LocalPath, LocalHash and TenantHash (the first twelve hex characters of the SHA-256 of each file)
and TenantModified (the policy's lastModifiedDateTime).

## NOTES

Author: Jeffrey Stuhr.
Needs a Microsoft.Graph.Authentication session with
DeviceManagementConfiguration.Read.All, DeviceManagementScripts.Read.All and
DeviceManagementApps.Read.All.
The module does not depend on the Graph SDK; it uses the
session the caller connected.

A byte order mark and the line endings matter because the agent runs the bytes as uploaded:
Windows PowerShell 5.1 reads UTF-8 without a BOM as ANSI (Validation\Findings.md).

## RELATED LINKS

- [Test-IntuneDeployedScript]()
- [Test-IntuneScript]()
