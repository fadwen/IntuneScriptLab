---
document type: cmdlet
external help file: IntuneScriptLab-Help.xml
HelpUri: https://github.com/fadwen/IntuneScriptLab/blob/main/docs/IntuneScriptLab/Repair-IntuneScript.md
Locale: en-US
Module Name: IntuneScriptLab
ms.date: 09/28/2026
PlatyPS schema version: 2024-05-01
title: Repair-IntuneScript
---

# Repair-IntuneScript

## SYNOPSIS

Applies the mechanical fixes for findings that have one, and reports what is left.

## SYNTAX

### __AllParameterSets

```
Repair-IntuneScript [-Path] <string[]> [-ScriptType <string>] [-IncludeRule <string[]>]
 [-ExcludeRule <string[]>] [-Settings <Object>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Runs Test-IntuneScript and rewrites each script for the findings whose rule knows a safe,
behaviour-preserving edit:

    IslExitCodeIssue   a script-scope 'return' becomes the exit it already implied:
                       'return' turns into 'exit 0', 'return <value>' into '<value>; exit 0'.
                       The script does the same as before, and now says so; whether that
                       exit should have been 1 is still the author's call
    IslEncodingIssue   a UTF-8 file without a BOM that holds non-ASCII text, a UTF-16 file
                       or an ANSI file (read in the system ANSI code page, so its characters
                       survive) is rewritten as UTF-8 with a BOM, the encoding Intune expects
    IslOutputIssue     a requirement script's output literal with leading or trailing
                       whitespace is trimmed, so it can match the portal value

Everything else stays as it is and is counted in Remaining.
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

## PARAMETERS

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
