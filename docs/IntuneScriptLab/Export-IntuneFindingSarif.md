---
document type: cmdlet
external help file: IntuneScriptLab-Help.xml
HelpUri: https://github.com/fadwen/IntuneScriptLab/blob/main/docs/IntuneScriptLab/Export-IntuneFindingSarif.md
Locale: en-US
Module Name: IntuneScriptLab
ms.date: 09/28/2026
PlatyPS schema version: 2024-05-01
title: Export-IntuneFindingSarif
---

# Export-IntuneFindingSarif

## SYNOPSIS

Writes IntuneScriptLab findings as a SARIF 2.1.0 log for code scanning.

## SYNTAX

### __AllParameterSets

```
Export-IntuneFindingSarif [-Finding] <psobject[]> [-Path] <string> [[-Root] <string>]
 [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Turns the findings Test-IntuneScript produces into one SARIF run: the IntuneScriptLab tool
with a rule entry per rule seen (its description from the rule's own help and, as its level,
that of the most severe finding it produced in this log), and a result per finding with the
file, line, column and text of the offending
code, the message, the observed Intune behaviour as a property and, for a finding a
Suppress directive silenced, an in-source suppression.
File paths are written relative to
-Root under the %SRCROOT% base, which is what GitHub code scanning and Azure DevOps expect.

Upload the file with github/codeql-action/upload-sarif and every finding appears in the
Security tab and on the pull request, with the evidence text alongside the message.
The
CI gate (Examples\Invoke-IntuneScriptGate.ps1 -SarifPath) writes it as part of a run.

## EXAMPLES

### EXAMPLE 1

Test-IntuneScript -Path .\Intune -IncludeSuppressed | Export-IntuneFindingSarif -Path .\results.sarif

Every finding, suppressed ones marked as such, in a file ready for upload-sarif.

### EXAMPLE 2

$findings = Test-IntuneScript -Path .\Remediations -MinimumSeverity Warning
Export-IntuneFindingSarif -Finding $findings -Path $env:RUNNER_TEMP\isl.sarif -Root $env:GITHUB_WORKSPACE

Warnings and errors only, paths relative to the checkout on a GitHub runner.

### EXAMPLE 3

Export-IntuneFindingSarif -Finding @() -Path .\results.sarif

A valid log with no results, so a clean run still uploads and closes earlier alerts.

## PARAMETERS

### -Finding

The IntuneScriptLab.Finding objects, from Test-IntuneScript or the pipeline.

```yaml
Type: System.Management.Automation.PSObject[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: true
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Path

The .sarif file to write.
Its folder is created; an existing file is replaced.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 1
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Root

The folder file paths are made relative to.
Default: GITHUB_WORKSPACE, or the current
directory.
A finding outside it gets an absolute file URI with no base.

```yaml
Type: System.String
DefaultValue: $(if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path })
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 2
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

### IntuneScriptLab.Finding

The findings from Test-IntuneScript, by value; an empty collection produces a valid log with no results.

### System.Management.Automation.PSObject[]

The IntuneScriptLab.Finding objects as PowerShell passes them by value.

## OUTPUTS

### System.IO.FileInfo

The SARIF file written.

## NOTES

Author: Jeffrey Stuhr.
Levels map Error to error, Warning to warning and Information to
note.
The rule descriptions come from the rule functions' help, so they stay in step with
the rules themselves.

## RELATED LINKS

- [Test-IntuneScript]()
- [Uploading a SARIF file to GitHub](https://docs.github.com/code-security/code-scanning/integrating-with-code-scanning/uploading-a-sarif-file-to-github)
