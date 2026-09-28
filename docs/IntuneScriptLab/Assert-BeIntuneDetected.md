---
document type: cmdlet
external help file: IntuneScriptLab-Help.xml
HelpUri: https://github.com/fadwen/IntuneScriptLab/blob/main/docs/IntuneScriptLab/Assert-BeIntuneDetected.md
Locale: en-US
Module Name: IntuneScriptLab
ms.date: 09/28/2026
PlatyPS schema version: 2024-05-01
title: Assert-BeIntuneDetected
---

# Assert-BeIntuneDetected

## SYNOPSIS

Asserts a Win32 detection result counts as installed (alias Should-BeIntuneDetected).

## SYNTAX

### __AllParameterSets

```
Assert-BeIntuneDetected [[-Actual] <Object>] [-Because <string>] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Passes when Invoke-IntuneDetectionTest reported Detected.
On failure the message carries
the reason Intune would give: the exit code, missing stdout, or output on stderr.

## EXAMPLES

### EXAMPLE 1

Invoke-IntuneDetectionTest -Path .\Detect-App.ps1 | Should-BeIntuneDetected

The app must be detected on this machine.

### EXAMPLE 2

Invoke-IntuneDetectionTest -Path .\Detect-App.ps1 -Architecture x86 |
    Should-BeIntuneDetected -Because 'the rule is set to run as 32-bit'

Same, in the 32-bit host, with the reason in the failure message.

### EXAMPLE 3

$result | Should-NotBeIntuneDetected

The opposite check, for a machine where the app is absent.

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

Why detection matters; quoted in the failure message.

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

From Invoke-IntuneDetectionTest; Detected must be true.

### System.Object

The result object piped into the assertion. New-ShouldAssertion collects the pipeline, so the assertion also accepts the object as its positional argument.

## OUTPUTS

### System.Void

Throws a Pester assertion failure when the app is not detected; the message carries the Reason.

## NOTES

Author: Jeffrey Stuhr.
Every rule and verdict is backed by observations recorded in
Validation\Findings.md (documented vs observed Intune behaviour).

## RELATED LINKS

- [Invoke-IntuneDetectionTest]()
- [Assert-NotBeIntuneDetected]()
