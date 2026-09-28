---
document type: cmdlet
external help file: IntuneScriptLab-Help.xml
HelpUri: https://github.com/fadwen/IntuneScriptLab/blob/main/docs/IntuneScriptLab/Assert-BeIntuneApplicable.md
Locale: en-US
Module Name: IntuneScriptLab
ms.date: 09/28/2026
PlatyPS schema version: 2024-05-01
title: Assert-BeIntuneApplicable
---

# Assert-BeIntuneApplicable

## SYNOPSIS

Asserts a requirement result meets its rule (alias Should-BeIntuneApplicable).

## SYNTAX

### __AllParameterSets

```
Assert-BeIntuneApplicable [[-Actual] <Object>] [-Because <string>] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Passes when Invoke-IntuneRequirementTest reported Applicable.
On failure the message
carries the reason the agent would give: the exit code, stderr, an output that did not
parse as the rule's type, or the value that did not meet the operator.

## EXAMPLES

### EXAMPLE 1

Invoke-IntuneRequirementTest -Path .\Requirement.ps1 -OutputType String -Value 'ok' |
    Should-BeIntuneApplicable

Fails with the reason when the output would not satisfy the rule.

### EXAMPLE 2

$result | Should-BeIntuneApplicable -Because 'the agent is installed on the test machine'

With a reason for the failure message.

### EXAMPLE 3

Assert-BeIntuneApplicable $result

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

Why the requirement should be met; quoted in the failure message.

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

From Invoke-IntuneRequirementTest; Applicable must be true.

### System.Object

The result object piped into the assertion. New-ShouldAssertion collects the pipeline, so the assertion also accepts the object as its positional argument.

## OUTPUTS

### System.Void

Nothing. Throws a Pester assertion failure when the rule is not met; the message carries the reason the agent would give.

## NOTES

Author: Jeffrey Stuhr.
Every rule and verdict is backed by observations recorded in
Validation\Findings.md (documented vs observed Intune behaviour).

## RELATED LINKS

- [Invoke-IntuneRequirementTest]()
- [Assert-NotBeIntuneApplicable]()
