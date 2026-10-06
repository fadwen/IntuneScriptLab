---
document type: cmdlet
external help file: IntuneScriptLab-Help.xml
HelpUri: https://github.com/fadwen/IntuneScriptLab/blob/main/docs/IntuneScriptLab/Repair-IntuneScript.md
Locale: en-US
Module Name: IntuneScriptLab
ms.date: 10/06/2026
PlatyPS schema version: 2024-05-01
title: Repair-IntuneScript
---

# Repair-IntuneScript

## SYNOPSIS

Applies the mechanical fixes for findings that have one, and reports what is left.

## SYNTAX

### __AllParameterSets

```
Repair-IntuneScript [-Path] <string[]> [-ScriptType <string>] [-Context <string>]
 [-Architecture <string>] [-IncludeRule <string[]>] [-ExcludeRule <string[]>]
 [-EnforceSignatureCheck] [-Settings <Object>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Runs Test-IntuneScript and rewrites each script for the findings whose rule knows a safe,
behaviour-preserving edit:

    IslExitCodeIssue   a script-scope 'return' becomes the exit it already implied:
                       'return' turns into 'exit 0', 'return <value>' into '<value>; exit 0'.
                       The script does the same as before, and now says so; whether that
                       exit should have been 1 is still the author's call. A return with an
                       exit other than 0 after it in the same block ('return 1; exit 1') is
                       left alone: the author meant that exit, and the finding stays until
                       a person decides
    IslEncodingIssue   a UTF-8 file without a BOM that holds non-ASCII text, a UTF-16 file
                       or an ANSI file (read in the system ANSI code page, so its characters
                       survive) is rewritten as UTF-8 with a BOM, the encoding Intune expects
    IslOutputIssue     a requirement script's output literal with leading or trailing
                       whitespace is trimmed, so it can match the portal value; a probing
                       cmdlet without -ErrorAction gets -ErrorAction SilentlyContinue, so a
                       missing target no longer writes to stderr
    IslInteractiveCall Install-Module, Install-PackageProvider, Install-Package, Update-Module
                       and Uninstall-Module get -Force, Register-PSRepository gets
                       -Confirm:$false; a Get-Credential -Credential handed a credential that
                       can only be one already built is replaced by that credential
    IslExecutionPolicyCall
                       a Set-ExecutionPolicy call that is a statement of its own is removed;
                       the agent launches the script with -ExecutionPolicy Bypass
    IslExitCodeIssue   'exit N' with N other than 0 or 1 becomes 'exit 1', the value Intune
                       reads it as
    IslArchitectureIssue
                       $env:ProgramFiles becomes $env:ProgramW6432, the 64-bit folder in
                       either host
    IslArm64Assumption 'AMD64' as the pattern of a -match becomes 'ARM64|AMD64'
    IslRelativePath    $PWD becomes $PSScriptRoot where no member follows it
    IslPowerShell7Syntax
                       a '#Requires -Version 7' line is removed; what the script then does
                       under Windows PowerShell 5.1, the other findings say

Everything else stays as it is and is counted in Remaining. Where an edit would leave a broken
statement, Set-ExecutionPolicy inside a pipeline, 'AMD64' compared with -eq, $PWD.Path, the
finding has no fix and stays.
Text edits are applied from the
end of the file backwards so line numbers stay valid, line endings are kept, and an edit
whose text no longer matches the file is skipped with a warning.
The command supports
-WhatIf and -Confirm; nothing is written under -WhatIf.

## EXAMPLES

### EXAMPLE 1

Repair-IntuneScript -Path .\Remediations -WhatIf

Lists the edits that would be made, per script, without touching anything.

### EXAMPLE 2

Repair-IntuneScript -Path .\Remediations\Widget\Detect.ps1

Applies the fixes and reports how many findings the script still has.

### EXAMPLE 3

Get-ChildItem .\Win32 -Recurse -Filter Requirement*.ps1 | Repair-IntuneScript -IncludeRule IslOutputIssue

Trims padded requirement values only, in every requirement script under Win32.

### EXAMPLE 4

Repair-IntuneScript -Path .\Remediations -Architecture x64 -Context System

Repairs the scripts as deployed to the 64-bit host in system context, so the findings that depend
on either, and the Remaining count, match Test-IntuneScript run with the same options.

## PARAMETERS

### -Architecture

The host the script runs in, passed to the analysis: x86 (portal default for scripts and
remediations), x64 (Win32 detection default) or arm64. Auto (default) infers per script as
Test-IntuneScript does. The findings an architecture decides, System32 against Sysnative among
them, and the fixes and Remaining count that follow from them, are then the ones
Test-IntuneScript gives for the same value.

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

### -Confirm

Prompts you for confirmation before running the cmdlet.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases:
- cf
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

### -Context

System or User, passed to the analysis. Auto (default) uses the directive or the type's portal
default, as Test-IntuneScript does. HKCU: and the profile variables are errors under System and
not under User, so Remaining follows the context the script is deployed in.

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

### -EnforceSignatureCheck

Analyze Win32 detection and requirement scripts as if the rule's "Enforce script signature
check" were on: an unsigned script gets an IslSignatureIssue error, which has no fix and is
counted in Remaining. The directive comment "# IntuneScriptLab: EnforceSignatureCheck=true"
does the same for one script, and the settings key EnforceSignatureCheck = $true for a folder.

```yaml
Type: System.Management.Automation.SwitchParameter
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

### -ExcludeRule

Rule names (wildcards allowed) whose findings are not fixed.

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

### -IncludeRule

Rule names (wildcards allowed) whose findings are fixed; everything else is left alone.

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

### -Path

Scripts or folders (searched recursively for .ps1 files), also from the pipeline.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: true
Aliases:
- FullName
- PSPath
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

### -ScriptType

Passed to the analysis when every script is of one type; Auto (default) infers per script.

```yaml
Type: System.String
DefaultValue: Auto
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

### -Settings

A settings file path or hashtable, as for Test-IntuneScript.

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

### -WhatIf

Runs the command in a mode that only reports what would happen without performing the actions.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases:
- wi
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

### System.String[]

Paths, or objects with a FullName property such as the FileInfo objects Get-ChildItem returns.

## OUTPUTS

### IntuneScriptLab.Repair

One per script: Path, Applied (fixes made, or that would be made under -WhatIf), Remaining (findings still reported after the fixes; under -WhatIf, the findings minus the fixes), Written (whether the file changed; false under -WhatIf) and Fixes, one IntuneScriptLab.Fix per edit with RuleName, Line (0 for the encoding), Before and After.

## NOTES

Author: Jeffrey Stuhr.
A fix is behaviour-preserving by design: it makes explicit what the
script already did, or changes the file's encoding, never what the script decides.

## RELATED LINKS

- [Test-IntuneScript]()
