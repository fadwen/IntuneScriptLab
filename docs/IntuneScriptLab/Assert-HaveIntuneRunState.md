---
document type: cmdlet
external help file: IntuneScriptLab-Help.xml
HelpUri: ''
Locale: en-US
Module Name: IntuneScriptLab
ms.date: 09/28/2026
PlatyPS schema version: 2024-05-01
title: Assert-HaveIntuneRunState
---

# Assert-HaveIntuneRunState

## SYNOPSIS

Asserts the RunState of a platform script result (alias Should-HaveIntuneRunState).

## SYNTAX

### __AllParameterSets

```
Assert-HaveIntuneRunState [-Expected] <string> [[-Actual] <Object>] [-Because <string>]
 [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

For IntuneScriptLab.PlatformScriptResult: 'Success', 'Failed' or 'TimedOut'.
On failure
the message carries the actual state, the exit code and the start of the output.

## EXAMPLES

### EXAMPLE 1

Invoke-IntunePlatformScriptTest -Path .\Configure.ps1 | Should-HaveIntuneRunState 'Success'

The script must succeed.

### EXAMPLE 2

Invoke-IntunePlatformScriptTest -Path .\Configure.ps1 -Architecture x64 |
    Should-HaveIntuneRunState 'Success' -Because 'the policy runs it in 64-bit'

In the 64-bit host, with the reason.

### EXAMPLE 3

$result | Should-HaveIntuneRunState 'Failed'

A script that is expected to fail on this machine.

## PARAMETERS

### -Actual

The result object, usually piped from Invoke-IntunePlatformScriptTest.

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

Why the state matters; quoted in the failure message.

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

The run state Intune should show.

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

### IntuneScriptLab.PlatformScriptResult

From Invoke-IntunePlatformScriptTest; RunState is compared with Expected.

### System.Object

The result object piped into the assertion. New-ShouldAssertion collects the pipeline, so the assertion also accepts the object as its positional argument.

## OUTPUTS

### System.Void

Throws a Pester assertion failure when the run state differs; the message carries the exit code and up to 300 characters of output.

## NOTES

Author: Jeffrey Stuhr.
Every rule and verdict is backed by observations recorded in
Validation\Findings.md (documented vs observed Intune behaviour).

## RELATED LINKS

- [Invoke-IntunePlatformScriptTest]()
