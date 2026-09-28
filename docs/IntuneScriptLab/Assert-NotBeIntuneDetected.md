---
document type: cmdlet
external help file: IntuneScriptLab-Help.xml
HelpUri: ''
Locale: en-US
Module Name: IntuneScriptLab
ms.date: 09/28/2026
PlatyPS schema version: 2024-05-01
title: Assert-NotBeIntuneDetected
---

# Assert-NotBeIntuneDetected

## SYNOPSIS

Asserts a Win32 detection result counts as not installed (alias Should-NotBeIntuneDetected).

## SYNTAX

### __AllParameterSets

```
Assert-NotBeIntuneDetected [[-Actual] <Object>] [-Because <string>] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Passes when Invoke-IntuneDetectionTest reported not detected.
On failure the message shows
the exit code and stdout that made Intune count the app as installed.

## EXAMPLES

### EXAMPLE 1

Invoke-IntuneDetectionTest -Path .\Detect-App.ps1 | Should-NotBeIntuneDetected

On a machine without the app, the rule must not report it installed.

### EXAMPLE 2

$result | Should-NotBeIntuneDetected -Because 'the package was uninstalled in BeforeAll'

With the reason in the failure message.

### EXAMPLE 3

$result | Should-BeIntuneDetected

The opposite check.

## PARAMETERS

### -Actual

The IntuneScriptLab.DetectionResult, usually piped.

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

Why non-detection matters; quoted in the failure message.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### IntuneScriptLab.DetectionResult

From Invoke-IntuneDetectionTest; Detected must be false.

### System.Object

The result object piped into the assertion. New-ShouldAssertion collects the pipeline, so the assertion also accepts the object as its positional argument.

## OUTPUTS

### System.Void

Throws a Pester assertion failure when the app is detected; the message carries the exit code and stdout that counted as installed.

## NOTES

Author: Jeffrey Stuhr.
Every rule and verdict is backed by observations recorded in
Validation\Findings.md (documented vs observed Intune behaviour).

## RELATED LINKS

- [Invoke-IntuneDetectionTest]()
- [Assert-BeIntuneDetected]()
