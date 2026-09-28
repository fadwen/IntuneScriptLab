---
document type: cmdlet
external help file: IntuneScriptLab-Help.xml
HelpUri: ''
Locale: en-US
Module Name: IntuneScriptLab
ms.date: 09/28/2026
PlatyPS schema version: 2024-05-01
title: Assert-NotBeIntuneApplicable
---

# Assert-NotBeIntuneApplicable

## SYNOPSIS

Asserts a requirement result fails its rule (alias Should-NotBeIntuneApplicable).

## SYNTAX

### __AllParameterSets

```
Assert-NotBeIntuneApplicable [[-Actual] <Object>] [-Because <string>] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Passes when Invoke-IntuneRequirementTest reported not applicable.
On failure the message
quotes the output that met the rule.

## EXAMPLES

### EXAMPLE 1

Invoke-IntuneRequirementTest -Path .\Requirement.ps1 -OutputType String -Value 'ok' |
    Should-NotBeIntuneApplicable

Fails, quoting the output, when the rule would be met.

### EXAMPLE 2

$result | Should-NotBeIntuneApplicable -Because 'the prerequisite is absent here'

With a reason for the failure message.

### EXAMPLE 3

Assert-NotBeIntuneApplicable $result

The function name, without the Should- alias.

## PARAMETERS

### -Actual

The IntuneScriptLab.RequirementResult, usually from the pipeline.

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

Why the requirement should not be met; quoted in the failure message.

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

### IntuneScriptLab.RequirementResult

From Invoke-IntuneRequirementTest; Applicable must be false.

### System.Object

The result object piped into the assertion. New-ShouldAssertion collects the pipeline, so the assertion also accepts the object as its positional argument.

## OUTPUTS

### System.Void

Nothing. Throws a Pester assertion failure when the rule is met; the message quotes the output that met it.

## NOTES

Author: Jeffrey Stuhr.
Every rule and verdict is backed by observations recorded in
Validation\Findings.md (documented vs observed Intune behaviour).

## RELATED LINKS

- [Invoke-IntuneRequirementTest]()
- [Assert-BeIntuneApplicable]()
