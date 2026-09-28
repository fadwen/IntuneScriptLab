---
document type: cmdlet
external help file: IntuneScriptLab-Help.xml
HelpUri: https://github.com/fadwen/IntuneScriptLab/blob/main/docs/IntuneScriptLab/Assert-PassIntuneAnalysis.md
Locale: en-US
Module Name: IntuneScriptLab
ms.date: 09/28/2026
PlatyPS schema version: 2024-05-01
title: Assert-PassIntuneAnalysis
---

# Assert-PassIntuneAnalysis

## SYNOPSIS

Asserts Test-IntuneScript finds nothing at Warning or above (alias Should-PassIntuneAnalysis).

## SYNTAX

### __AllParameterSets

```
Assert-PassIntuneAnalysis [[-Actual] <Object>] [-MinimumSeverity <string>] [-ScriptType <string>]
 [-Because <string>] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Runs Test-IntuneScript on the path and fails with the list of findings, each with its line,
severity, rule and message, so the test output is the fix list.

## EXAMPLES

### EXAMPLE 1

'.\Detect.ps1' | Should-PassIntuneAnalysis

No warnings or errors for the script, with its type inferred from the name.

### EXAMPLE 2

Get-ChildItem .\Remediations -Filter *.ps1 | Should-PassIntuneAnalysis -ScriptType Detection

Every file, analyzed as a remediation detection script.

### EXAMPLE 3

'.\Detect-App.ps1' | Should-PassIntuneAnalysis -MinimumSeverity Error -ScriptType Win32Detection

Only findings that would make the detection rule report not detected.

## PARAMETERS

### -Actual

The script path, or a FileInfo from Get-ChildItem.
Usually piped.

```yaml
Type: System.Object
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: false
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Because

Why a clean analysis matters; quoted in the failure message.

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

### -MinimumSeverity

The lowest severity that counts as a failure.
Default Warning.

```yaml
Type: System.String
DefaultValue: Warning
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

### -ScriptType

Passed to Test-IntuneScript.
Default Auto (directive comment or file name).

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### System.String

The path of one script to analyze.

### System.IO.FileInfo

One script from Get-ChildItem; its FullName is analyzed.

### System.Object

The result object piped into the assertion. New-ShouldAssertion collects the pipeline, so the assertion also accepts the object as its positional argument.

## OUTPUTS

### System.Void

Throws a Pester assertion failure listing every finding at MinimumSeverity or above, one per line as file:line [Severity] Rule: message.

## NOTES

Author: Jeffrey Stuhr.
Every rule and verdict is backed by observations recorded in
Validation\Findings.md (documented vs observed Intune behaviour).

## RELATED LINKS

- [Test-IntuneScript]()
