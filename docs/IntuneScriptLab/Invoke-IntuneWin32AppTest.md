---
document type: cmdlet
external help file: IntuneScriptLab-Help.xml
HelpUri: https://github.com/fadwen/IntuneScriptLab/blob/main/docs/IntuneScriptLab/Invoke-IntuneWin32AppTest.md
Locale: en-US
Module Name: IntuneScriptLab
ms.date: 09/28/2026
PlatyPS schema version: 2024-05-01
title: Invoke-IntuneWin32AppTest
---

# Invoke-IntuneWin32AppTest

## SYNOPSIS

Runs a Win32 app's detect → install → detect flow the way the Intune agent does.

## SYNTAX

### __AllParameterSets

```
Invoke-IntuneWin32AppTest [[-DetectionPath] <string>] [[-DetectionRule] <hashtable[]>]
 [-ContentPath] <string> [[-InstallCommand] <string>] [[-UninstallCommand] <string>]
 [[-Intent] <string>] [[-DependsOn] <hashtable[]>] [[-Supersedes] <hashtable[]>]
 [[-Architecture] <string>] [[-Context] <string>] [[-Credential] <pscredential>]
 [[-InstallContext] <string>] [[-ReturnCodes] <hashtable>] [[-TimeoutSeconds] <int>]
 [[-InstallTimeoutSeconds] <int>] [-EnforceSignatureCheck] [<CommonParameters>]
```

## ALIASES

## DESCRIPTION

Reproduces the observed Win32 sequence: detect; if the app is not detected (intent Install)
or is detected (intent Uninstall), run the install or uninstall command from a copy of the
content folder; then detect again.

Detection is the detection script (-DetectionPath), file, registry and product code rules
(-DetectionRule, evaluated by Test-IntuneWin32Rule), or both. Every rule and the script must
say installed for the app to count as detected, as the agent does with several rules
(W32-MULTI-ONEFALSE, W32-MULTI-BOTHTRUE). With -EnforceSignatureCheck an unsigned detection
script is not run at all and counts as not detected (W32-DET-SIGCHECK).

Statuses:

    Installed                detected before any install
    Installed after install  install succeeded and the post-detection passed
    Not detected after install
                             install returned a success code but detection still fails,
                             Intune's 0x87D1041C "app installed but not detected"
    Install failed (exit N)  exit code not in the success/reboot/retry codes
    Retry                    exit code mapped to retry (Intune retries 3 times, 5 min apart)
    Not installed            intent Uninstall and nothing was detected, so nothing ran
    Uninstalled              the uninstall command succeeded and the post-detection no longer
                             reports the app (W32-UNINSTALL: Intune shows "Not installed")
    Still detected after uninstall
                             the uninstall command succeeded but the detection still says installed
    Uninstall failed (exit N)
                             uninstall exit code not in the success/reboot/retry codes
    Not installed (dependency)
                             a dependency was not detected and could not be installed (a detect
                             dependency, a missing install command, or a failed install), so this
                             app's install never ran (W32-DEPD-PARENT)
    TimedOut                 a step hit its timeout

Relationships (-DependsOn, -Supersedes) run in the observed order: this app's detection, then each
dependency's detection, install and detection, then each superseded app's detection and, for a
replace, its uninstall and detection, then this app's install and detection. Every related app
gets an IntuneScriptLab.Win32RelatedResult in Dependencies or Superseded.

Launch shape, from the observations: the detection script runs in the 64-bit host by
default (Win32 default) via the same launch as Invoke-IntuneDetectionTest; the install
command runs through a 32-bit cmd.exe, so a bare `powershell.exe` resolves to the x86
host exactly as it does under the agent's own 32-bit process, with the content copy as
working directory.
Soft/hard reboot codes count as success but are reported.

## EXAMPLES

### EXAMPLE 1

Invoke-IntuneWin32AppTest -DetectionPath .\Detect-App.ps1 -ContentPath .\Package `
    -InstallCommand 'powershell.exe -ExecutionPolicy Bypass -File install.ps1'

Full flow as the current user, 64-bit detection, 32-bit install command.

### EXAMPLE 2

Invoke-IntuneWin32AppTest -DetectionPath .\Detect-App.ps1 -ContentPath .\Package `
    -InstallCommand 'setup.exe /S' -Context System -InstallTimeoutSeconds 1800

As SYSTEM from an elevated session, which is what Intune does by default.

### EXAMPLE 3

$r = Invoke-IntuneWin32AppTest -DetectionPath .\Detect-App.ps1 -ContentPath .\Package `
    -InstallCommand 'msiexec /i app.msi /qn'
$r.Status; $r.Install.StdOut

Inspect the installer's output after the run.

### EXAMPLE 4

$rules = @(
    @{ Type = 'File'; Path = '%ProgramFiles%\Vendor'; FileOrFolderName = 'app.exe'; OperationType = 'version'
       Operator = 'greaterThanOrEqual'; ComparisonValue = '2.0' }
    @{ Type = 'Registry'; KeyPath = 'HKEY_LOCAL_MACHINE\SOFTWARE\Vendor\App'; ValueName = 'Installed'
       OperationType = 'integer'; Operator = 'equal'; ComparisonValue = '1' }
)
Invoke-IntuneWin32AppTest -DetectionRule $rules -ContentPath .\Package -InstallCommand 'setup.exe /S'

Detection by two portal-style rules with no script; both must be met, and the ones that are not
are listed in Warnings with the reason.

### EXAMPLE 5

Invoke-IntuneWin32AppTest -DetectionPath .\Detect-App.ps1 -ContentPath .\Package -Intent Uninstall `
    -UninstallCommand 'setup.exe /uninstall /S' | Should-HaveIntuneStatus 'Uninstalled'

The uninstall flow the agent runs for an uninstall assignment: detect, run the uninstall command,
detect again.

### EXAMPLE 6

$runtime = @{
    Name = 'Vendor Runtime'; DetectionPath = '.\Runtime\Detect-Runtime.ps1'
    ContentPath = '.\Runtime\Package'; InstallCommand = 'runtime.exe /S'
}
$previous = @{
    Name = 'App 1.x'; DetectionRule = @(@{ Type = 'ProductCode'; ProductCode = '{7F1E...}' })
    ContentPath = '.\App1\Package'; UninstallCommand = 'msiexec /x {7F1E...} /qn'; Type = 'replace'
}
$r = Invoke-IntuneWin32AppTest -DetectionPath .\Detect-App.ps1 -ContentPath .\Package `
    -InstallCommand 'setup.exe /S' -DependsOn $runtime -Supersedes $previous
$r.Dependencies | Format-Table Name, Relationship, Status
$r.Superseded | Format-Table Name, Relationship, Status

The relationships page of an app: the runtime is installed first if it is missing, the 1.x
package is uninstalled if it is present, then the app installs.

## PARAMETERS

### -Architecture

Host for the detection script: x64 (Intune default), x86, or arm64. A Windows on ARM device has no x64 host, so a -DetectionPath with the x64 default is refused there: pass arm64.

```yaml
Type: System.String
DefaultValue: x64
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 8
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ContentPath

The folder that would be packaged as the .intunewin (copied before use; the copy is
the working directory of the install command).

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 2
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Context

User (default) or System. System runs the detection and the install command as NT AUTHORITY\SYSTEM
through a one-shot scheduled task (elevated session required) and matches the Intune default for
Win32 apps. User runs them as the account running this command, which is right for apps set to
install in the user's context but cannot impersonate the signed-in user the agent would use.

```yaml
Type: System.String
DefaultValue: User
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 9
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Credential

Run every launch (the detection script, the related apps' detections, the install or uninstall command) as this account instead of the current user, with -Context User: a one-shot scheduled task registered for the account, interactive inside the account's own session when it holds one (the way the agent runs user-context scripts inside the signed-in user's session, REM-PROBE-USER64), otherwise a stored-password logon in session 0, which needs the account to hold the "Log on as a batch job" right (a standard user does not; the scheduler then never starts the task, and the launcher reports that within seconds rather than at the timeout); the result's RunAs says which. Needs an elevated session, and is refused with -Context System. Validation\New-IslHarnessUser.ps1 creates a lab account with a stored credential to use here.

```yaml
Type: System.Management.Automation.PSCredential
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 10
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -DependsOn

The app's dependencies, one hashtable each with Name, DetectionPath and/or DetectionRule (the same
shapes as this app's), ContentPath, InstallCommand and Type: autoInstall (default) or detect. They
are handled after this app's first detection says not installed, in the order given, as the agent
was observed to (W32-DEP-PARENT): an autoInstall dependency that is not detected is installed from
its content and detected again before this app installs; a detect dependency that is absent, or a
dependency whose install fails, stops the flow with Not installed (dependency).

```yaml
Type: System.Collections.Hashtable[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 6
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -DetectionPath

The custom detection script. Optional when -DetectionRule is given; with both, the script and
every rule must report installed.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -DetectionRule

File, registry and product code detection rules as hashtables, in the shape Test-IntuneWin32Rule
-Rule takes (Type File, Registry or ProductCode with Path, FileOrFolderName, KeyPath, ValueName,
ProductCode, OperationType, Operator, ComparisonValue, Check32BitOn64System, or the Graph
win32LobApp*Rule properties). All of them must be met.

```yaml
Type: System.Collections.Hashtable[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 1
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -EnforceSignatureCheck

The rule's "Enforce script signature check". An unsigned detection script is then not run at
all and reports not detected, as AgentExecutor did (W32-DET-SIGCHECK).

```yaml
Type: System.Management.Automation.SwitchParameter
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

### -InstallCommand

The install command line as entered in Intune, e.g.
'powershell.exe -ExecutionPolicy Bypass -File install.ps1'. Required with -Intent Install.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 3
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -InstallContext

The app's install behavior in the portal, System (default) or User. User adds a warning: an
assignment to a device group never installs a user-context app, the agent reports Not applicable
after a "userless check-in" (W32-USER-INSTALL), so assign such an app to users.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 11
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -InstallTimeoutSeconds

Timeout for the install command.
Default 10 minutes (Intune: 60).

```yaml
Type: System.Int32
DefaultValue: 600
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 14
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Intent

Install (default) runs -InstallCommand when the app is not detected. Uninstall runs
-UninstallCommand when it is detected, the flow an uninstall assignment triggers.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 5
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ReturnCodes

Exit code → outcome map for the install command.
Default is Intune's:
0 and 1707 success, 3010 soft reboot, 1641 hard reboot, 1618 retry.

```yaml
Type: System.Collections.Hashtable
DefaultValue: >-
  @{
              0 = 'success'; 1707 = 'success'; 3010 = 'softReboot'; 1641 = 'hardReboot'; 1618 = 'retry'
          }
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 12
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Supersedes

The apps this one supersedes, one hashtable each with Name, DetectionPath and/or DetectionRule,
ContentPath, UninstallCommand and Type: update (default) or replace. Each is detected before this
app installs. An update target is left in place (W32-SUP-OLD-A); a replace target that is
detected has its uninstall command run from its content and is detected again before this app's
install (W32-SUP-OLD-B). A replace target that survives its uninstall is reported in Warnings.

```yaml
Type: System.Collections.Hashtable[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 7
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -TimeoutSeconds

Per-step timeout for the detection scripts.
Default 5 minutes (Intune: 60).

```yaml
Type: System.Int32
DefaultValue: 300
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 13
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -UninstallCommand

The uninstall command line as entered in Intune; required with -Intent Uninstall.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 4
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

### None

This command does not accept pipeline input. Pass the paths, rules and commands as parameters.

## OUTPUTS

### IntuneScriptLab.Win32AppResult

Status (Installed, Installed after install, Not detected after install, Install failed (exit n), Retry, Not installed, Not installed (dependency), Uninstalled, Still detected after uninstall, Uninstall failed (exit n) or TimedOut), Intent, the PreDetection and PostDetection script results, PreRules and PostRules (one IntuneScriptLab.RuleResult per detection rule), Dependencies and Superseded (one IntuneScriptLab.Win32RelatedResult per related app, with Name, Relationship, Status and its own detections, rules and install or uninstall run), the Install or Uninstall run (command, exit code, output), Warnings, RunAs (the account and logon type the launches ran as), Architecture and Context.

## NOTES

Author: Jeffrey Stuhr.
Every rule and verdict is backed by observations recorded in
Validation\Findings.md (documented vs observed Intune behaviour).

SECURITY: -InstallCommand is executed verbatim through cmd.exe, exactly as Intune executes the
install command, as the current user or as SYSTEM.
Only run packages you trust, on a test
machine or a snapshot.
PERFORMANCE: the content folder is copied; installers run with a 10-minute default timeout.

## RELATED LINKS

- [Invoke-IntuneDetectionTest]()
- [Test-IntuneScript]()
- [Should-HaveIntuneStatus]()
