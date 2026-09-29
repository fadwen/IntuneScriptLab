---
document type: cmdlet
external help file: IntuneScriptLab-Help.xml
HelpUri: https://github.com/fadwen/IntuneScriptLab/blob/main/docs/IntuneScriptLab/Assert-HaveIntuneStatus.md
Locale: en-US
Module Name: IntuneScriptLab
ms.date: 09/28/2026
PlatyPS schema version: 2024-05-01
title: Assert-HaveIntuneStatus
---

# Assert-HaveIntuneStatus

## SYNOPSIS

Asserts a remediation or Win32 result Status (alias Should-HaveIntuneStatus).

## SYNTAX

### __AllParameterSets

```
Assert-HaveIntuneStatus [-Expected] <string> [[-Actual] <Object>] [-Because <string>]
 [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

For IntuneScriptLab.RemediationResult ('Without issues', 'Issue detected (no remediation
script)', 'Fixed', 'Recurred', 'Failed', 'TimedOut') and IntuneScriptLab.Win32AppResult
('Installed', 'Installed after install', 'Not detected after install', 'Install failed (exit
N)', 'Retry', 'Not installed', 'Not installed (dependency)', 'Uninstalled', 'Still detected
after uninstall', 'Uninstall failed (exit N)', 'TimedOut').
On failure
the message carries what Intune would have shown: the actual status, the reported output
and error, and the harness warnings.

## EXAMPLES

### EXAMPLE 1

Invoke-IntuneRemediationTest -DetectionPath .\Detect.ps1 -RemediationPath .\Remediate.ps1 |
    Should-HaveIntuneStatus 'Fixed'

The full flow must end Fixed.

### EXAMPLE 2

$result | Should-HaveIntuneStatus 'Without issues' -Because 'the baseline image is compliant'

Detection alone, with the reason in the failure message.

### EXAMPLE 3

Invoke-IntuneWin32AppTest -DetectionPath .\Detect-App.ps1 -ContentPath .\Package `
    -InstallCommand 'setup.exe /S' | Should-HaveIntuneStatus 'Installed after install'

A Win32 package that must install and then be detected.

## PARAMETERS

### -Actual

The result object, usually piped from Invoke-IntuneRemediationTest or
Invoke-IntuneWin32AppTest.

```yaml
Type: System.Object
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 1
  IsRequired: false
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Because

Why the status matters; quoted in the failure message.

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

### -Expected

The status the portal should show.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### IntuneScriptLab.RemediationResult

From Invoke-IntuneRemediationTest; Status is compared with Expected.

### IntuneScriptLab.Win32AppResult

From Invoke-IntuneWin32AppTest; Status is compared with Expected.

### System.Object

The result object piped into the assertion. New-ShouldAssertion collects the pipeline, so the assertion also accepts the object as its positional argument.

## OUTPUTS

### System.Void

Throws a Pester assertion failure when the status differs; the message carries IntuneOutput, IntuneError and any Warnings from the result.

## NOTES

Author: Jeffrey Stuhr.
Every rule and verdict is backed by observations recorded in
Validation\Findings.md (documented vs observed Intune behaviour).

## RELATED LINKS

- [Invoke-IntuneRemediationTest]()
- [Invoke-IntuneWin32AppTest]()
