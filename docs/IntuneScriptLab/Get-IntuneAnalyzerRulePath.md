---
document type: cmdlet
external help file: IntuneScriptLab-Help.xml
HelpUri: https://github.com/fadwen/IntuneScriptLab/blob/main/docs/IntuneScriptLab/Get-IntuneAnalyzerRulePath.md
Locale: en-US
Module Name: IntuneScriptLab
ms.date: 09/28/2026
PlatyPS schema version: 2024-05-01
title: Get-IntuneAnalyzerRulePath
---

# Get-IntuneAnalyzerRulePath

## SYNOPSIS

Returns IntuneScriptLab's PSScriptAnalyzer rule module, for -CustomRulePath.

## SYNTAX

### __AllParameterSets

```
Get-IntuneAnalyzerRulePath [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

The module ships its rules a second time as PSScriptAnalyzer custom rules, one Measure-*
function per IntuneScriptLab rule (Measure-IslExitCodeIssue, Measure-IslOutputIssue and so
on, plus Measure-IslAssumedContext for the context note), as
PSScriptAnalyzer\IntuneScriptLab.Rules.psm1 under the module base.
This command returns
that file's path so a call to Invoke-ScriptAnalyzer, a PSScriptAnalyzerSettings.psd1 or an
editor's analyzer settings can point at it without knowing where the module was installed.
PSScriptAnalyzer 1.25 did not find the rules when given the folder in any layout, so the
file path is what to pass.

Under PSScriptAnalyzer each rule reports the same findings Test-IntuneScript reports, with
the observed Intune behaviour appended to the message, so the checks run next to the
built-in rules in the same pass, the same CI gate and the same editor squiggles.
-IncludeRule and -ExcludeRule take the Measure-* names.

## EXAMPLES

### EXAMPLE 1

Invoke-ScriptAnalyzer -Path .\Remediations -Recurse -CustomRulePath (Get-IntuneAnalyzerRulePath) -IncludeDefaultRules

Every script under Remediations checked by the built-in rules and the IntuneScriptLab rules. Without
-IncludeDefaultRules a -CustomRulePath runs the custom rules alone.

### EXAMPLE 2

Invoke-ScriptAnalyzer -Path .\Detect-App.ps1 -CustomRulePath (Get-IntuneAnalyzerRulePath) `
    -IncludeDefaultRules:$false -ExcludeRule Measure-IslAssumedContext

Only the IntuneScriptLab rules, without the note about the assumed script type.

### EXAMPLE 3

$rules = Get-IntuneAnalyzerRulePath
"@{ CustomRulePath = '$rules'; IncludeDefaultRules = `$true }" |
    Set-Content .\PSScriptAnalyzerSettings.psd1

Writes a PSScriptAnalyzerSettings.psd1 that includes the rules in every run.

## PARAMETERS

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### None

This command takes no input.

## OUTPUTS

### System.String

The full path of PSScriptAnalyzer\IntuneScriptLab.Rules.psm1 in the installed module, ready for -CustomRulePath.

## NOTES

Author: Jeffrey Stuhr.
PSScriptAnalyzer invokes a custom rule once per script block in a
file; the wrapper analyzes the file once at the root and answers from a cache for the rest.

## RELATED LINKS

- [Test-IntuneScript]()
