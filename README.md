# IntuneScriptLab

[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/IntuneScriptLab?style=flat-square&logo=powershell&label=Gallery)](https://www.powershellgallery.com/packages/IntuneScriptLab)
[![Quality Gates](https://img.shields.io/github/actions/workflow/status/fadwen/IntuneScriptLab/quality-gates.yml?branch=main&style=flat-square&label=quality%20gates)](https://github.com/fadwen/IntuneScriptLab/actions/workflows/quality-gates.yml)
[![PowerShell 5.1](https://img.shields.io/badge/PowerShell-5.1+-blue?style=flat-square&logo=powershell)](https://github.com/PowerShell/PowerShell)
[![Pester](https://img.shields.io/badge/Tested_with-Pester_6-green?style=flat-square)](https://pester.dev)
[![Intune](https://img.shields.io/badge/Intune-Management_Extension-orange?style=flat-square&logo=microsoft)](https://learn.microsoft.com/en-us/mem/intune/apps/intune-management-extension)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](./LICENSE)

Test Intune PowerShell scripts before Intune does: remediation detection and remediation
scripts, platform scripts, and Win32 app detection and requirement scripts.

- **Static analysis**: `Test-IntuneScript` finds the mistakes Intune turns into silent
  failures without running anything (exit-code traps, output Intune drops, SYSTEM and 32-bit
  path redirection, PowerShell 7-only syntax, prompts that hang, encoding).
- **Runtime harness**: `Invoke-IntuneRemediationTest`, `Invoke-IntuneDetectionTest`,
  `Invoke-IntuneRequirementTest`, `Invoke-IntunePlatformScriptTest` and `Invoke-IntuneWin32AppTest` run the script the way the
  Intune Management Extension does (same host, flags, working directory, SYSTEM via scheduled
  task) and report what the portal would show: Fixed, Recurred, not detected, and why.
  `Test-IntuneWin32Rule` applies a file, registry or MSI rule to the machine the way the agent
  evaluates it, and `Invoke-IntuneWin32AppTest` runs those rules, the uninstall flow and the
  enforced signature check. `Test-IntuneAssignmentFilter` evaluates an assignment filter rule
  against this device the way the service does.
- **Pester**: `Should-HaveIntuneStatus 'Fixed'`, `Should-BeIntuneApplicable` and friends for your own
  test suites (Pester 6.2+).

Every rule and every verdict is backed by what real devices did, not only by the docs (see
[Validation/Findings.md](https://github.com/fadwen/IntuneScriptLab/blob/main/Validation/Findings.md)). No Intune connection needed; runs on
Windows PowerShell 5.1 and PowerShell 7; x86, x64 and ARM64 hosts.

## Prerequisites

| Layer | Needs |
|---|---|
| Static analysis (`Test-IntuneScript`) | Windows PowerShell 5.1 or PowerShell 7 on any OS. No modules, no Intune connection. |
| Runtime harness (`Invoke-Intune*Test`) | Windows with Windows PowerShell 5.1 (in-box). x86 and x64 hosts on x64 Windows; x86 and ARM64 on ARM64 Windows. |
| `-Context System` | An elevated session: the script is run through a scheduled task registered as SYSTEM. |
| Pester assertions (`Should-*IntuneStatus` etc.) | Pester 6.2 or later. |

## Installation

```powershell
# From the PowerShell Gallery
Install-PSResource -Name IntuneScriptLab

# On Windows PowerShell 5.1 without PSResourceGet
Install-Module -Name IntuneScriptLab -Scope CurrentUser

# From a clone of this repository (the repository root is the module root)
Import-Module .\IntuneScriptLab.psd1
```

```powershell
Test-IntuneScript -Path .\Detect-LegacyTls.ps1 -ScriptType Detection
Test-IntuneScript -Path .\Detect-App.ps1 -ScriptType Win32Detection | Where-Object Severity -eq Error
Get-ChildItem .\Remediations -Recurse -Filter *.ps1 | Test-IntuneScript -MinimumSeverity Warning
```

Each finding has `RuleName`, `Severity`, `Message`, `ScriptPath`, `Line`, `Column`, `Text` (the
offending code) and `Evidence` (the observed behaviour the rule rests on).

## Rules

The full reference, every message each rule can produce with the observation and experiment ids
behind it, is generated from the rule files: [docs/Rules.md](https://github.com/fadwen/IntuneScriptLab/blob/main/docs/Rules.md) (`Build/Build-RuleReference.ps1`;
the unit tests fail when it is stale). `Get-Help about_IntuneScriptLab` is the conceptual overview.

| Rule | What it catches | Observed behaviour behind it |
|---|---|---|
| `IslPowerShell7Syntax` | Ternary, `&&`/`\|\|`, `??`, `?.`, `-Parallel`, `#Requires -Version 7`, 7-only cmdlets, parameters and parameter values | Scripts run under Windows PowerShell 5.1. A parse error or an unmet `#Requires` makes a detection exit 1 (remediation runs) and a Win32 detection "not detected". A 7-only cmdlet, parameter or value parses: the call fails and the script carries on to its own exit |
| `IslEncodingIssue` | Non-ASCII in a UTF-8 file without BOM; UTF-16; non-ASCII in reported output | Files arrive byte-for-byte; without a BOM, 5.1 decodes them as ANSI. Output goes through the OEM code page |
| `IslInteractiveCall` | `Read-Host`, `Pause`, `Get-Credential`, `Out-GridView`, console reads, confirming cmdlets without `-Force` | The agent never passes `-NonInteractive`; prompts hang until the 30/60-minute timeout. `Get-Credential -Credential` handed a credential that is already built returns it, so a variable there is a warning, not an error |
| `IslExitCodeIssue` | `return` before `exit 1`, exit codes other than 0/1, unhandled `throw`, missing `exit` | Any non-zero exit runs the remediation; `return` ends the script with exit 0 (Microsoft's own samples do this); `throw` exits 1 |
| `IslOutputIssue` | A trailing `Write-Host`/`Warning`/`Verbose` displacing the summary; many `Write-Output` lines; Win32 detection: no stdout, `Write-Error`, unguarded cmdlets; Win32 requirement: a second output line (`Write-Host` included), whitespace in the value, no output, `Write-Error`, non-zero exit | Remediations report the last console line (last 2,048 chars), host streams included: a trailing `Write-Warning` is reported as `WARNING: ...`. Win32 detection: installed = exit 0 **and** stdout; any stderr = not detected; `Write-Host` counts as stdout. Win32 requirement: the whole console output minus its final line break is compared (case-insensitively for strings), so a second line or trailing spaces never match; exit 1 or stderr fails the rule |
| `IslContextIssue` | `HKCU:`, `$env:APPDATA`/`USERPROFILE`, per-user folders in SYSTEM scripts, and a note on drive letters other than `C:`, which may be mapped drives; HKLM writes and service control in user scripts; a note that user context needs an Entra-joined device | SYSTEM runs in session 0 with the `systemprofile` profile and `C:\WINDOWS\TEMP`, sees local volumes and not the drives the signed-in user mapped; user context runs as the signed-in user, and only on Entra joined / hybrid-joined devices: on an Entra-registered device the agent downloads the policy and skips it ("not AADJ/HAADJ device") |
| `IslArchitectureIssue` | `HKLM:\SOFTWARE`, `Program Files`, `System32` in 32-bit scripts; `Sysnative` in 64-bit | `runAs32Bit` launches `SysWOW64\...\powershell.exe`; the portal defaults scripts and remediations to 32-bit |
| `IslArm64Assumption` | `'AMD64'` used to mean "64-bit", x64-only installers, `Program Files (x86)` checked without `Program Files (Arm)` | On Windows on ARM the native host reports `ARM64`; the x86 host is emulated and reports `ARCHITEW6432=ARM64`; there is no x64 PowerShell host (local survey of an ARM64 device) |
| `IslRebootCommand` | `Restart-Computer`, `Stop-Computer`, `shutdown /r` | Unsupported in remediations; a reboot loses the run result |
| `IslRelativePath` | `.\path`, `$PWD` | Working directory is `system32`, the Win32 content folder, or whatever the agent last used |
| `IslLongSleep` | `Start-Sleep` near or over the timeout | 30 min (platform scripts) / 60 min (remediations, Win32); remediations run one at a time |
| `IslSignatureIssue` | An unsigned Win32 detection or requirement script when the rule's signature check is on (`-EnforceSignatureCheck` or `# IntuneScriptLab: EnforceSignatureCheck=true`) | With the check enforced the agent does not run an unsigned script at all: AgentExecutor returns exit 1, the app is "not detected", the install runs and ends in 0x87D1041C |
| `IslExecutionPolicyCall` | `Set-ExecutionPolicy` at process scope (note) or any other scope (warning) | The agent launches every script with `-ExecutionPolicy Bypass`; inside a remediation the process scope is Bypass and every other scope Undefined, so the call is redundant at best and a lasting policy change as SYSTEM at worst |
| `IslModuleDependency` | `Import-Module`, `#Requires -Modules` or `using module` naming a module outside the in-box list; `Install-Module`, `Install-PSResource` and the like inside the script | SYSTEM's module path under the agent is a relative `WindowsPowerShell\Modules`, `Program Files\WindowsPowerShell\Modules` and the System32 modules (90 on a plain Windows 11 device); `#Requires` for a missing module stops the script before it runs; `Install-Module` blocks on the NuGet provider prompt until the 60-minute timeout and holds every other remediation on the device behind it |
| `IslScriptSize` | A file over the documented 200 KB (warning) or over what the service refused (error) | The API accepted a 504 KB remediation and a 660 KB platform script and refused 512 KB and 680 KB; a 250 KB remediation and a 500 KB platform script ran on the device |

## Script type, context and architecture

They decide which rules apply. Pass them, put a directive in the script, or let the file name
decide:

```powershell
# IntuneScriptLab: ScriptType=Detection Context=System Architecture=x64
```

| Inferred from the path | ScriptType | Default context | Default architecture |
|---|---|---|---|
| `requirement` | Win32Requirement | System | x64 |
| `detect` under a `Win32`, `Apps` or `Packages` folder (two levels up at most), or with `app`, `apps`, `win32`, `package`, `software`, `install`, `installed`, `msi` or `exe` in the name (`Detect-App.ps1`, `Detect-Package.ps1`) | Win32Detection | System | x64 |
| `detect` under a `Remediations` or `HealthScripts` folder, or any other `detect` | Detection | System | x86 |
| `remediat`, `fix` | Remediation | System | x86 |
| anything else | PlatformScript | User | x86 |

Each word matches at the start of a word in the file name or a folder name: `Get-Requirement.ps1`
is a requirement script, `Get-AppRequirement.ps1` is not.

Defaults follow the **portal**. Scripts created through the Graph API get 64-bit SYSTEM instead,
so the same script can behave differently depending on how it was deployed. Every inferred file
gets an `IslAssumedContext` note saying what was assumed; `-ExcludeRule IslAssumedContext` (or
`-MinimumSeverity Warning`) silences it once the assumptions are known to be right.

`-Architecture` is the *host* the script runs in, not the CPU:

| Value | Host | Where |
|---|---|---|
| `x86` | `SysWOW64\WindowsPowerShell\v1.0\powershell.exe` (WOW64 redirection applies) | x64 and ARM64 devices (emulated on ARM64) |
| `x64` | `System32\...\powershell.exe`, native x64 | x64 devices only |
| `arm64` | `System32\...\powershell.exe`, native ARM64 | ARM64 devices only; there is no x64 host there |

For a mixed fleet run the analysis once per host you deploy to, e.g. `x86` and `arm64`.

## Suppressions and settings (0.13)

```powershell
# One line, from a trailing or preceding directive; the whole file from the header
Start-Sleep -Seconds 600   # IntuneScriptLab: Suppress=IslLongSleep

# IntuneScriptLab: ScriptType=Remediation Suppress=IslLongSleep,IslOutput*
```

A `Suppress=` entry in the `# IntuneScriptLab:` directive silences a rule (wildcards allowed): in
the header before the first statement it covers the file, on a line of its own the next line of
code, at the end of a line that line. Suppressed findings are dropped; `-IncludeSuppressed` shows
them with `Suppressed` set, so a review can still see what was waved through.

A file named `IntuneScriptLab.settings.psd1` in the scripts' folder or any folder above them
applies to every script below it (the nearest one wins):

```powershell
@{
    ExcludeRule     = @('IslAssumedContext')
    MinimumSeverity = 'Information'
    Severity        = @{ IslLongSleep = 'Information' }   # keep the rule, lower the stakes
    ScriptType      = 'Remediation'                        # when a script's directive says nothing
    Context         = 'System'
    Architecture    = 'x64'
}
```

Explicit parameters win over the file (`-ExcludeRule` adds to the file's list, `-IncludeRule` sets it
aside), and a script's directive wins over its type, context, architecture and signature entries.
`-Settings` takes a path or a hashtable instead of the search (`@{}` for none) on `Test-IntuneScript`,
`Repair-IntuneScript`, `Test-IntuneDeployedScript`, `Compare-IntuneDeployedScript`,
`Get-IntuneScriptHealth` and the CI gate; the
PSScriptAnalyzer rules and the gate pick the file up on their own.
[Examples/IntuneScriptLab.settings.psd1](./Examples/IntuneScriptLab.settings.psd1) is a commented
template.

## Fixing what can be fixed (0.15)

```powershell
Repair-IntuneScript -Path .\Remediations -WhatIf

Applied Remaining Written Fixes                          Path
------- --------- ------- -----                          ----
      1         3 False   IslExitCodeIssue@4             C:\repo\Remediations\Widget\Detect.ps1
      1         0 False   IslEncodingIssue@0             C:\repo\Remediations\Widget\Remediate.ps1
```

Three findings come with an edit the tool can make for you, each behaviour-preserving: a
script-scope `return` becomes the `exit 0` it already produced, with any returned value written
first (`return 'ok'` to `'ok'; exit 0`); a UTF-16 or BOM-less non-ASCII file is rewritten as UTF-8
with a BOM; a padded requirement value (`' ok '`) is trimmed. `Repair-IntuneScript` applies them
per script, reports what it changed and how many findings remain, and previews with `-WhatIf`.
Whether that `exit 0` should have been an `exit 1` is still the author's call, which is why the
finding stays an error until the intent is made explicit. Where the script already says which exit
was meant, a `return` with an exit other than 0 after it in the same block (`return 1; exit 1`),
there is no edit: `1; exit 0; exit 1` would behave the same, hide the exit the author wrote and
leave no finding behind, so that one stays for a person. Findings carry the edit as `Fix`.

## Runtime harness (0.2)

Runs a script the way the Intune Management Extension does and interprets the result the way
Intune does. `-Context User` (the default) runs it as whoever is running the harness: Intune runs
user-context scripts as the signed-in user, which the harness cannot impersonate, so treat that
mode as "the launch shape and the output rules" and `-Context System` as exact.

```powershell
# Detect -> remediate if the detection exits non-zero -> detect again
Invoke-IntuneRemediationTest -DetectionPath .\Detect.ps1 -RemediationPath .\Remediate.ps1 -Architecture x86

Status        : Recurred
IntuneOutput  : Registry value missing        # last stdout line, last 2,048 chars, OEM code page
IntuneError   :
PreDetection  : exit 1 in 0.9 s
Remediation   : exit 0 in 0.7 s
PostDetection : exit 1 in 0.8 s
Warnings      : {Detection wrote 3 lines; Intune reports only the last one}

# Win32 custom detection: installed only with exit 0, stdout and no stderr
Invoke-IntuneDetectionTest -Path .\Detect-App.ps1 -Architecture x64

# Win32 requirement rule: the rule as configured in the portal, applied the way the agent applies it
Invoke-IntuneRequirementTest -Path .\Get-AgentVersion.ps1 -OutputType Version -Operator GreaterThanOrEqual -Value '2.9.0'

Applicable : True
Reason     : Output '2.10.0' meets Version GreaterThanOrEqual '2.9.0'

# Platform script: Success/Failed, full output
Invoke-IntunePlatformScriptTest -Path .\Configure.ps1
```

What is reproduced (each from an observation in `Validation/Findings.md`): Windows PowerShell
5.1 in the chosen host (`SysWOW64` for x86, `System32` for x64/arm64), `-NoProfile
-ExecutionPolicy Bypass -File` with no `-NonInteractive`, working directory
`C:\WINDOWS\system32`, the script run from a copy so `$PSScriptRoot` is not the source folder,
output through the OEM code page, a timeout that kills the process tree, any non-zero detection
exit triggering the remediation, the Without issues / Fixed / Recurred / Failed mapping, last
line + 2,048-character tail for remediations, full output for platform scripts.

### SYSTEM context (0.3)

`-Context System` on any of the runtime functions runs the script as `NT AUTHORITY\SYSTEM` in
session 0, where the agent runs it, through a one-shot scheduled task (`cmd.exe` redirects the
output to files; the task is removed afterwards; a timeout stops it and kills anything it
started). It needs an elevated session. Verified on an Entra-joined test VM under Windows
PowerShell 5.1: identity, session, working directory, host bitness, the Fixed flow, the Win32
flow and timeout cleanup all matched the agent's behaviour.

```powershell
Invoke-IntuneRemediationTest -DetectionPath .\Detect.ps1 -RemediationPath .\Remediate.ps1 -Context System
```

### Running as another account (0.18)

```powershell
$cred = Import-Clixml C:\ProgramData\IntuneScriptLab\isl-user.cred.xml   # or Get-Credential
Invoke-IntuneRemediationTest -DetectionPath .\Detect.ps1 -RemediationPath .\Remediate.ps1 -Context User -Credential $cred

Status : Fixed
RunAs  : LAB-042\isl-user (Interactive)
```

The agent runs user-context scripts as the signed-in user, inside that user's own session (session
2, `UserInteractive` true, the user's profile, TEMP and APPDATA; REM-PROBE-USER64). Running the
harness as yourself gets that only for your own account, so `-Credential` on every
`Invoke-Intune*Test` command runs the script as another account through a one-shot scheduled task,
the same mechanism as `-Context System`: when the account holds a logon session the task is
interactive and runs inside it, which is the agent's shape; when it does not, the task is registered
with the password ("run whether user is logged on or not") and runs in session 0 with the account's
profile loaded, and `RunAs` says `(Password)` so you know the session differs; that logon needs
the "Log on as a batch job" right, which a standard user does not have by default, and the launcher
reports the refusal with that hint within seconds, whether the scheduler answers `0x80070569` or
simply never starts the task (`0x00041303`, "has not run yet", which is what the lab device does
today). Needs an elevated session. On
the lab device the interactive path reproduced the agent's launch point for point (console session,
`UserInteractive` true, the account's profile paths, system32; `Validation/Findings.md`, "The
harness as another account"). The script copy and its output live under `ProgramData\IntuneScriptLab\Runs` with the
account granted Modify, since another account cannot reach your temp folder.
[Validation/New-IslHarnessUser.ps1](https://github.com/fadwen/IntuneScriptLab/blob/main/Validation/New-IslHarnessUser.ps1) creates a standard lab
account with a generated password stored as a DPAPI credential, and the `UserContext` integration
suite runs against it when `ISL_TEST_CREDENTIAL` points at that file.

### Win32 app flow (0.3)

```powershell
Invoke-IntuneWin32AppTest -DetectionPath .\Detect-App.ps1 -ContentPath .\Package `
    -InstallCommand 'powershell.exe -ExecutionPolicy Bypass -File install.ps1' -Context System

Status        : Not detected after install
PreDetection  : detected=False exit 0: Nothing on stdout: exit 0 alone is "not detected"
Install       : exit 0 in 4.1 s
PostDetection : detected=False exit 0: Nothing on stdout: exit 0 alone is "not detected"
Warnings      : {powershell.exe in the install command runs the 32-bit host ..., Post-install detection: ... Intune reports 0x87D1041C ...}
```

Detect → install → detect, as the agent does it. The install command runs through a 32-bit
`cmd.exe` from a copy of the content folder, so a bare `powershell.exe` resolves to the x86 host
exactly as under the agent's own 32-bit process. Return codes follow Intune's defaults (0/1707
success, 3010/1641 reboot, 1618 retry) and can be overridden with `-ReturnCodes`.

Deviations: `User` is the default context (SYSTEM needs elevation); stdin is an empty
stream rather than a hidden console, so a `Read-Host` returns immediately instead of hanging
(`Test-IntuneScript` flags those); default timeouts are 5–10 minutes, not Intune's 30/60.

### Win32 rules, uninstall and signature check (0.6)

```powershell
# A portal-style rule against this machine, evaluated the way the agent evaluates it
Test-IntuneWin32Rule -KeyPath 'HKEY_LOCAL_MACHINE\SOFTWARE\Vendor\App' -ValueName Version `
    -RegistryOperation Version -Operator GreaterThanOrEqual -Value '9.0'

Met    : True
Reason : Value in the 64-bit view: '10.0.1' meets Version GreaterThanOrEqual '9.0'

# Detection by rules instead of (or as well as) a script; every rule must be met
$rules = @(
    @{ Type = 'File'; Path = '%ProgramFiles%\Vendor'; FileOrFolderName = 'app.exe'; OperationType = 'version'
       Operator = 'greaterThanOrEqual'; ComparisonValue = '2.0' }
    @{ Type = 'ProductCode'; ProductCode = '{FBE4D84C-C935-4F54-B96F-49316CEB5149}' }
)
Invoke-IntuneWin32AppTest -DetectionRule $rules -ContentPath .\Package -InstallCommand 'setup.exe /S'

# The uninstall flow an uninstall assignment triggers: detect, uninstall, detect
Invoke-IntuneWin32AppTest -DetectionPath .\Detect-App.ps1 -ContentPath .\Package -Intent Uninstall `
    -UninstallCommand 'setup.exe /uninstall /S'
```

What the rules do, each from a round-5 experiment (`Validation/Findings.md`, "Win32 file, registry
and MSI rules"):

- **File**: `%VARIABLE%` paths expand in the 64-bit context, or in the 32-bit one with
  `-Check32BitOn64System`, where `%ProgramFiles%` is `Program Files (x86)`. `Version` compares the
  file version as a version (10.0.26100.x is above 9.0), `SizeInMB` whole MiB rounded down,
  `ModifiedDate`/`CreatedDate` in UTC. `DoesNotExist` is accepted by the Graph API but the agent
  cannot evaluate it on a file: a missing file is "not detected" and a present one is an
  invalid-rule error (0x87D30004). The command reports it not met either way and says why.
- **Registry**: the 64-bit view, or the `WOW6432Node` view with `-Check32BitOn64System`. `Exists`
  and `DoesNotExist` work on a key or a value; `String` compares case-insensitively; `Integer`
  parses the value even from a `REG_SZ`; `Version` compares as a version.
- **ProductCode**: 64-bit, 32-bit and per-user products are all found; a version operator compares
  `DisplayVersion` as a version.
- **`-EnforceSignatureCheck`** on `Invoke-IntuneDetectionTest` and `Invoke-IntuneWin32AppTest`: an
  unsigned detection script is not run at all and counts as not detected, which is what
  AgentExecutor did.
- **Platform scripts**: a failed run carries a warning with what Intune does next, three runs in
  total at the agent's script policy fetches (a service start or restart, otherwise every 8
  hours), then Failed for good.

### Win32 base requirements and assignment facts (0.7)

```powershell
Test-IntuneWin32Requirement -Architecture x64 -MinimumWindowsRelease Windows11_23H2 -MinimumMemoryMB 4096

Applicable    : True
Applicability : 0
Reason        : Every requirement is met (3 checked); the detection runs next

Test-IntuneWin32Requirement -Architecture arm64

Applicable    : False
Details       : Device architecture (e.g. x86/amd64) is not applicable for the application.
Applicability : 1000
```

The Requirements page of an app, evaluated against this device with the portal text and the
device-side code the agent produced in the round-6 experiments (architecture 1000, disk space 1001,
memory 1003, logical processors 1004; the minimum-OS and CPU-speed texts were not observed and the
result says so). Facts from the same round that the harness now tells you about rather than
emulates:

- A user install context app assigned to a device group is never installed on either join type
  ("userless check-in", Not applicable, code 1011); `Invoke-IntuneWin32AppTest -InstallContext User`
  warns about it.
- Assignment filters decide before anything runs: a filtered-out device reports "Filters criteria
  are not met." and keeps no state for the app.
- Dependencies install the child first (autoInstall) or refuse the parent with "1 or more dependent
  apps are configured to not automatically install." (detect); supersedence `update` leaves the old
  app installed, `replace` runs its uninstall command before the new install.
- Script and remediation policy is fetched at an agent start or restart and otherwise every 8
  hours; Win32 apps arrive by push within minutes, and installed or not-applicable apps are
  re-detected about 8 hours later.
- A detect-only remediation is one created without a remediation script. The assignment's
  `runRemediationScript` only reflects whether one was uploaded: set to false through the Graph
  beta API on a policy that has one, it changed nothing and the remediation ran every hour; the
  same policy recreated with a detection script alone ran the detection alone.

### Win32 dependencies and supersedence (0.8)

```powershell
$runtime = @{
    Name = 'Vendor Runtime'; DetectionPath = '.\Runtime\Detect-Runtime.ps1'
    ContentPath = '.\Runtime\Package'; InstallCommand = 'runtime.exe /S'      # Type autoInstall
}
$previous = @{
    Name = 'App 1.x'; DetectionRule = @(@{ Type = 'ProductCode'; ProductCode = '{7F1E...}' })
    ContentPath = '.\App1\Package'; UninstallCommand = 'msiexec /x {7F1E...} /qn'; Type = 'replace'
}
Invoke-IntuneWin32AppTest -DetectionPath .\Detect-App.ps1 -ContentPath .\Package `
    -InstallCommand 'setup.exe /S' -DependsOn $runtime -Supersedes $previous -Context System

Status        : Installed after install
Dependencies  : Vendor Runtime: Installed after install
Superseded    : App 1.x: Uninstalled
```

The relationships page of an app, run in the order the agent was observed to run it
(`Validation/Findings.md`, "Win32 requirements, filters, install context and relationships"):

- **Dependencies** come after this app's first detection. An `autoInstall` dependency that is not
  detected is installed and detected before this app's install runs (W32-DEP-PARENT); one that is
  already there is left alone. A `detect` dependency that is absent, or a dependency whose install
  fails, stops the flow with `Not installed (dependency)` and the portal text "1 or more dependent
  apps are configured to not automatically install." (W32-DEPD-PARENT).
- **Supersedence** is evaluated next. An `update` target stays installed (W32-SUP-OLD-A, the old
  app kept its marker and its Installed status); a `replace` target that is detected has its
  uninstall command run, and detected again, before the new install (W32-SUP-OLD-B: old uninstall
  at 09:07:14, new install at 09:07:47). A replace target that survives its uninstall is reported in
  Warnings.
- Each related app gets an `IntuneScriptLab.Win32RelatedResult` in `Dependencies` or `Superseded`
  with its own pre and post detection, rule results and install or uninstall run.

### Reading the agent's own logs (0.9)

```powershell
Get-IntuneAgentLog -Id bbf7e139-fe9d-4783-80df-627b8e084059 -After (Get-Date).AddHours(-1)

Time               Log            Event                 Detail             Message
----               ---            -----                 ------             -------
09-25 08:40:13.339 HealthScripts  RemediationSchedule   hourly             [HS] inspect hourly schedule for policy bbf7e139-...
09-25 08:45:14.201 HealthScripts  RemediationStart                         [HS] Runner: script bbf7e139-... will try to execute now.
09-25 08:45:26.874 HealthScripts  DetectionResult       pre False          [HS] the pre-remdiation detection script compliance result for bbf7e139-... is False
09-25 08:46:56.114 HealthScripts  RemediationReport     4                  [HS] new result = {"PolicyId":"bbf7e139-...","Result":4,...}
```

`Get-IntuneAgentLog` reads the Intune Management Extension's CMTrace logs
(IntuneManagementExtension, AppWorkload, HealthScripts, AgentExecutor, rolled files included) as
objects, merged in time order, and names the event each known line records. The event table is the
set of lines the validation rounds used as evidence: script policy fetches and download counts,
remediation schedule inspections, starts, detection verdicts and reports, Win32 policy fetches,
applicability, detection, rule evaluations, installs and reports, and AgentExecutor's exit codes
and script output (`-ListEvent` shows them all). Filter by `-Log`, `-Id` (policy or app),
`-EventName`, `-Level`, `-After`/`-Before`, `-Pattern` and `-Last`. The files are opened with
shared access, so the live agent is no obstacle, and a copied log folder works with `-Path`.

### The Enrollment Status Page (0.19)

```powershell
Get-IntuneAgentLog -EventName ScriptEspPhase, EspPhase, EspAppsSelected, EspAppRegistered,
    EspAppState, EspPhaseComplete, EspComplete, EspNontrackedCheckin

Time               Log                        Event                 Detail
----               ---                        -----                 ------
09-28 07:06:00.847 IntuneManagementExtension  ScriptEspPhase        DeviceSetup
09-28 07:06:12.299 AppWorkload                EspPhase              DeviceSetup
09-28 07:06:25.611 AppWorkload                EspAppsSelected       2
09-28 07:06:31.011 AppWorkload                EspAppRegistered      DeviceSetup ISL-ESP-DEV-W32-BLOCK1
09-28 07:07:31.199 AppWorkload                EspAppState           InProgress Completed
09-28 07:08:20.385 AppWorkload                EspPhaseComplete      device
09-28 07:08:37.882 AppWorkload                EspPhase              AccountSetup
09-28 07:11:22.504 AppWorkload                EspComplete
09-28 07:12:22.658 IntuneManagementExtension  EspNontrackedCheckin  True
```

One Autopilot run (Validation\Findings.md, "The Enrollment Status Page") fixed where scripts sit
relative to the page: a device-assigned SYSTEM platform script runs in the device setup phase
**before** the blocking apps and is not tracked, user-context platform scripts run at the start of
the account setup phase, remediations do not run during the page at all (the first run came three
minutes after it closed), a required app outside the blocking list starts 20 seconds after the page
closes, and a user-context script that writes to a SYSTEM-created file under ProgramData fails with
access denied and is reported as failed despite exit 0. The help of `Invoke-IntunePlatformScriptTest`
and `Invoke-IntuneRemediationTest` carries the same notes.

### Timelines and a diagnostic package (0.23)

```powershell
Get-IntuneAgentTimeline -Log HealthScripts, AppWorkload -After (Get-Date).AddHours(-2)

Started         Kind        Name                    Duration Runs Outcome                 Summary
-------         ----        ----                    -------- ---- -------                 -------
09-28 07:06:13  Win32App    ISL-ESP-DEV-W32-BLOCK1  00:01:18    1 AppReport 1             07:06:13 AppPolicyFetch > 07:06:19 AppDetection Success NotDetected > 07:07:08 AppExecution Install > 07:07:31 AppReport 1
09-28 07:10:02  Remediation bbe9b83f-882c-4ae7-...  00:07:02    1 RemediationReport 4     07:10:02 RemediationSchedule hourly > 07:15:28 RemediationStart > 07:15:41 DetectionResult pre True > 07:17:04 RemediationReport 4

Export-IntuneAgentDiagnostic -Path C:\Temp\intune-diag.zip

Path                     Files Logs Registry Timeline SizeBytes
----                     ----- ---- -------- -------- ---------
C:\Temp\intune-diag.zip     14    6     True     True   2318402
```

`Get-IntuneAgentTimeline` groups the named log lines by the policy or app they belong to, so one
object tells the story of one remediation, platform script or Win32 app: the steps in order, the
time between the first and the last, how many launches, and the last result the agent logged (apps
are named from the policy list the agent logs). `Export-IntuneAgentDiagnostic` packs the agent's
logs (copied with shared access), its registry state (policies, Win32 app states, script reports,
the enrollment's FirstSync values, the Enrollment Status Page tracking, the Autopilot diagnostics),
the device facts, `dsregcmd /status` and the parsed events and timelines as CSV into one zip for a
ticket. The event table also names the relationship lines the round-6 flows replay produced: the
subgraph an app is processed in, a skipped subgraph, the report that names the impacting app with
its classification and conflict reason, the dependency toast, the unassigned child's missing intent
and the content download step.

### Under PSScriptAnalyzer (0.10)

```powershell
Invoke-ScriptAnalyzer -Path .\Remediations -Recurse -CustomRulePath (Get-IntuneAnalyzerRulePath) -IncludeDefaultRules

RuleName                   Severity  ScriptName       Line  Message
--------                   --------  ----------       ----  -------
Measure-IslExitCodeIssue   Error     Detect.ps1       12    'return' at script scope ends the script with exit 0 ... [Observed: ...]
Measure-IslLongSleep       Error     Detect.ps1       15    Start-Sleep -Seconds 4000 exceeds the 3600 s timeout ... [Observed: ...]
PSAvoidUsingWriteHost      Warning   Remediate.ps1    3     File 'Remediate.ps1' uses Write-Host ...
```

The same rules as PSScriptAnalyzer custom rules, one `Measure-Isl*` function per rule plus
`Measure-IslAssumedContext` for the context note, so they run in the same pass, the same CI gate and
the same editor squiggles as the built-in rules. `Get-IntuneAnalyzerRulePath` returns the rule module
for `-CustomRulePath` or for a `PSScriptAnalyzerSettings.psd1`; `-IncludeRule` and `-ExcludeRule` take the
`Measure-` names (a `-CustomRulePath` switches the built-in rules off unless `-IncludeDefaultRules`
asks for them), and a `-ScriptDefinition` is analyzed too, with its type from a
`# IntuneScriptLab: ScriptType=...` directive. Each record carries the observed Intune behaviour
after the message. PSScriptAnalyzer hands a rule every script block in a file; the wrapper answers
at the root one only, where the file is analyzed once and the result cached for the rules that
follow.

`Invoke-ScriptAnalyzer -Severity` does not filter these records by their own severity.
PSScriptAnalyzer registers every custom rule as Warning and filters on that, so `-Severity Error`
returns none of them and `-Severity Warning` returns all of them, whatever each record says
(PSScriptAnalyzer 1.25.0). Filter the output instead: `... | Where-Object Severity -eq Error`.

### Pre-flight against the tenant (0.11)

```powershell
Connect-MgGraph -Scopes DeviceManagementScripts.Read.All, DeviceManagementConfiguration.Read.All,
    DeviceManagementApps.Read.All, GroupMember.ReadBasic.All
Test-IntuneDeployedScript -MinimumSeverity Warning

   Policy: Remediation 'Fix-Widget' (2b1c...)

Severity    Rule                   Role        Line Message
--------    ----                   ----        ---- -------
Error       IslExitCodeIssue       detection      4 'return' at script scope ends the script with exit 0 ...
Warning     IslEncodingIssue       detection        UTF-8 without a BOM: Windows PowerShell 5.1 reads it as ANSI ...

   Policy: Win32App 'Widget 2.0' (7f1e...)

Severity    Rule                   Role        Line Message
--------    ----                   ----        ---- -------
Error       IslDetectionRuleIssue  policy           Detection rule 2 is a file rule with detectionType doesNotExist ...
Warning     IslAssignmentIssue     policy           Install behavior User, assigned to devices ...
```

`Test-IntuneDeployedScript` reads what the tenant actually has (remediations, platform scripts,
Win32 apps) through your Microsoft.Graph session and runs the rules on every script they carry,
with the script type, run-as account, bitness and signature check taken from the policy rather
than inferred, so the verdict matches what the agent will do. Four deployment-level checks come
from the rounds: a file `doesNotExist` detection rule (the agent does not evaluate it, W32-FILE-NOTEXIST),
a user install context app assigned to a device group (never installed, W32-USER-INSTALL), a
remediation with no remediation script (detection runs alone, REM-DETECTONLY) and, since 0.17, an
assignment filter whose clause no Windows device can match (a `"x64"` architecture or a
`"Microsoft Entra joined"` trust type, FLT-V25 / FLT-E07; `IslFilterIssue`). Since 0.21 the
assignments themselves are checked too (round 9): a policy with no assignment or only exclusions
is never resolved by any device (Warning), a run-once schedule whose time has passed runs once at
the fetch on a device that has not run it (`IslScheduleIssue`, Information), and a user-context
script assigned to devices is skipped on Entra registered devices (Information). Filter by `-Kind`,
`-Name`, `-Id`, `-IncludeRule`/`-ExcludeRule` and `-MinimumSeverity`; `-SkipGroupLookup` leaves groups
alone. Nothing in the tenant is changed, and the module does not depend on the Graph SDK: it uses
the session you connected.

### Assignment filters (0.17)

```powershell
Test-IntuneAssignmentFilter -Rule '(device.deviceName -startsWith "LAB-") and (device.operatingSystemVersion -ge 10.0.26100)'

Applicable : False
Matched    : False
Mode       : Include
Reason     : Not applicable: the rule does not match this device; the portal shows "Filters criteria are not met." (W32-FILTER-INCLUDE)
Clauses    : device.deviceName -startsWith "LAB-" [not matched, actual: DESKTOP-P96U0KB]
             device.operatingSystemVersion -ge 10.0.26100 [matched, actual: 10.0.26200.9457]

Test-IntuneAssignmentFilter -Rule '(device.cpuArchitecture -eq "x64")' -SyntaxOnly
WARNING: 'x64' is not a value a Windows device reports for device.cpuArchitecture (amd64, x86, arm64, unknown); the clause at character 29 never matches
```

An assignment filter decides before anything runs, and until now the only way to try a rule was
the portal's Preview devices. `Test-IntuneAssignmentFilter` parses a rule the way the service's
`validateFilter` accepts and refuses it (114 rules probed: dashes and casing optional, `and` before
`or`, parentheses optional, lists only with `-in` / `-notIn`, `$null` only with `-eq` / `-ne`, no
`not`, no `-endsWith`, no single quotes, no escaped quotes, versions of 2 to 4 parts) and evaluates
it the way the service's evaluator matched two real devices (84 rules: case-insensitive, leading
and trailing spaces ignored, `-contains` a substring, a missing value an empty string,
`operatingSystemVersion` numeric with missing parts as 0). Without `-Device` it reads this machine
(name, manufacturer, model, build with UBR, the SKU name the reference uses, `amd64` / `arm64`,
join type from `dsregcmd`); pass a hashtable for another device or for the tenant-side values,
`-Mode Exclude` for an exclude filter, `-SyntaxOnly` to validate without a device, or pipe the
filters from Graph. A value the service accepts but no Windows device reports (`"x64"`,
`"Microsoft Entra joined"`) is a warning, and `Test-IntuneDeployedScript` reports the same on every
assignment that carries such a filter. Evidence: `Validation/Findings.md`, "Assignment filter
rules", produced by `Validation/Invoke-FilterProbe.ps1`.

### Drift against git (0.20)

```powershell
Compare-IntuneDeployedScript -Path C:\Repos\intune-scripts | Where-Object State -ne InSync

Kind           Policy          Role         State     Differences      Detail
----           ------          ----         -----     -----------      ------
Remediation    Fix-Widget      remediation  Drifted   Bom, Content     the local file has no BOM, the tenant's has one; content differs from line 4: local 'Remove-Item $cache -Recurse', tenant 'Remove-Item $cache' (1 line(s) only local, 1 only in the tenant)
PlatformScript Set-Proxy       script       Drifted   LineEndings      line endings LF locally, CRLF in the tenant
Remediation    Report-Only     detection    Missing                    no local file for the detection script of 'Report-Only' under C:\Repos\intune-scripts
Win32App       Widget 2.0      requirement  Drifted   Settings         Architecture=x86 locally, the policy runs x64
```

`Compare-IntuneDeployedScript` reads the same policies as the pre-flight and compares every script
they carry with its local copy byte for byte, so the tenant can be checked against the commit that
should be deployed. The local file is found by convention (a folder named after the policy holding
`Detect*.ps1` and `Remediat*.ps1` or `Requirement*.ps1`; a platform script as `<Name>.ps1`), or
named through `-Map`. A byte order mark, the line-ending style and trailing whitespace are reported
apart from content because the agent runs the bytes as uploaded, and a directive or settings file
that sets the context, architecture or signature check is compared with the policy's own settings.
Policies without a local file, ambiguous matches and local files the tenant has no script for are
states of their own, so `Where-Object State -ne InSync` is the whole gate.

### Health report (0.22)

```powershell
Get-IntuneScriptHealth -Path C:\Repos\intune-scripts -MarkdownPath .\intune-health.md | Where-Object Health -ne Healthy

Health    Kind           Policy               Err Warn Drift        OK  Fail Notes
------    ----           ------               --- ---- -----        --  ---- -----
Broken    Remediation    Report-Only            0    1              0     0 assigned to nobody; 1 warning finding(s)
Broken    PlatformScript Set-Proxy              0    0 InSync       0     2 every device that ran it failed
Attention Remediation    Fix-Widget             0    1 Drifted      4     1 1 warning finding(s); 1 device(s) failed; 2 device(s) still detect the issue; drift: Drifted
Attention Win32App       Widget 2.0             0    0 InSync       4     0 2 device(s) not applicable
```

`Get-IntuneScriptHealth` puts the tenant checks on one line per policy: the findings of
`Test-IntuneDeployedScript` counted by severity, the drift of `Compare-IntuneDeployedScript` when
`-Path` is given, the assignment (include targets, exclusions, filters) and what the devices reported
to Intune: a remediation's run summary (no issue or remediated, still detected or back, script
errors, pending), a platform script's run summary (succeeded, failed) and an app's install counts
from the AppInstallStatusAggregate export, one job of about twenty seconds for every app together
because the per-app status endpoints are gone from Graph. Health is Broken for an error finding, a
policy assigned to nobody or a policy every device failed; Attention for warnings, failures, a
remediation whose issue stays detected, drift or an assigned policy nobody has reported on yet;
Healthy otherwise, with the reasons in Notes. `-SkipAnalysis` and `-SkipRunState` leave parts out
(a remediation's run state reaches Graph with the agent's next hourly report, about an hour after
the run; a state that has not changed is not re-reported), `-MarkdownPath` writes the same report
as a Markdown table per kind, Broken first.

### In a GitHub Actions workflow (0.12)

```yaml
# The analyze step, in short; Examples/intune-script-gate.yml is the complete workflow
- name: Analyze
  shell: pwsh
  run: |
    $module = Get-Module -Name IntuneScriptLab -ListAvailable | Sort-Object Version -Descending |
        Select-Object -First 1
    & (Join-Path $module.ModuleBase 'Examples\Invoke-IntuneScriptGate.ps1') -Path ./Intune -FailOn Error
```

[Examples/intune-script-gate.yml](./Examples/intune-script-gate.yml) is a workflow to copy into a
repository of Intune scripts: on every pull request that touches a script it takes the module from a
checked-in copy when `ISL_MODULE_PATH` names its manifest, or installs it from the Gallery,
runs [Examples/Invoke-IntuneScriptGate.ps1](./Examples/Invoke-IntuneScriptGate.ps1) over the script
folders and fails the build at the chosen severity. The gate script annotates the changed files
with each finding (file, line, rule, message), appends a Markdown summary to the job, and returns
the findings with `-PassThru`; it works on any CI with `-Annotate:$false`. With `-SarifPath` it
also writes a SARIF 2.1.0 log (`Export-IntuneFindingSarif`: a rule entry per rule with its help
text, one result per finding with the relative path, line, snippet and evidence, in-source
suppressions for what a directive silenced), and the template's upload step puts those results in
the Security tab and on the pull request when `UPLOAD_SARIF` is switched on. A second, switched-off
job shows where the runtime harness fits once a Pester suite from the template exists.

## In your own Pester suite (0.4)

The module exports Pester 6.2 assertions (approved-verb `Assert-*` functions under `Should-*`
aliases, so `Import-Module` stays warning-free):

```powershell
BeforeAll { Import-Module IntuneScriptLab }

It 'passes static analysis'      { '.\Detect.ps1' | Should-PassIntuneAnalysis }
It 'fixes the issue'             { Invoke-IntuneRemediationTest -DetectionPath .\Detect.ps1 -RemediationPath .\Remediate.ps1 | Should-HaveIntuneStatus 'Fixed' }
It 'is not detected when absent' { Invoke-IntuneDetectionTest -Path .\Detect-App.ps1 | Should-NotBeIntuneDetected }
It 'runs'                        { Invoke-IntunePlatformScriptTest -Path .\Configure.ps1 | Should-HaveIntuneRunState 'Success' }
```

A failure message carries the diagnosis: the status Intune would show with its output and
warnings, the detection reason, or the list of findings with line numbers.
[Examples/IntuneScripts.Tests.ps1.template](./Examples/IntuneScripts.Tests.ps1.template) is a
complete suite for a folder of remediations, Win32 apps and platform scripts, with the SYSTEM
tests skipped unless elevated. On Pester 5, assert on the result properties directly
(`$result.Status | Should -Be 'Fixed'`).

## Tests

```powershell
Invoke-Pester .\Tests\Unit                       # fast: mocked launches, static analysis
Invoke-Pester .\Tests -Output Detailed           # everything, including the real-process suites
Invoke-Pester .\Tests -ExcludeTagFilter Elevated # skip the SYSTEM-context tests explicitly
```

| Folder | What it holds |
|---|---|
| `Tests/Unit/Public` | One suite per exported function. The runtime commands are tested with the process launch mocked, so the status mapping runs in milliseconds. |
| `Tests/Unit/Private` | A suite for most private helpers and, under `Rules/`, one per rule, calling the rule directly through `InModuleScope`. |
| `Tests/Integration` | The suites that start real Windows PowerShell 5.1 processes: launch shape, output as Intune reports it, the remediation and Win32 workflows, SYSTEM context (skipped unless elevated), and the assertions on real results. About a minute. |
| `Tests/TestHelpers` | Fixtures every suite dot-sources: `New-TestScript`, `Get-RuleFinding`, `New-Win32Fixture`, `Get-AssertionMessage`. |

Host coverage is split, not overlapping: the integration suites exercise the x64 runtime path on
the x64 CI runner and the arm64 path on an ARM64 development machine (each refuses the other's
64-bit host), and the x86 path on both. The Unit suites pass with PowerShell 7 and with Windows
PowerShell 5.1 as the module host: CI runs the whole suite on PowerShell 7, shuffled and with an
80% coverage gate, and the unit suites again on Windows PowerShell 5.1 and on the Windows on ARM
runner.

## Help

Command help is PlatyPS Markdown under [docs/IntuneScriptLab/](https://github.com/fadwen/IntuneScriptLab/tree/main/docs/IntuneScriptLab) compiled
into `en-US/IntuneScriptLab-Help.xml`, which is what `Get-Help` reads. Edit the Markdown, not the
functions' comment blocks (those carry only `.EXTERNALHELP` and a synopsis), then rebuild:

```powershell
Install-PSResource Microsoft.PowerShell.PlatyPS   # 1.0.3 or later, once
.\Build\Build-Help.ps1                            # refresh docs\ from the module, compile en-US\
```

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `IslAssumedContext` finding on every script | The script type was inferred from the file name. Pass `-ScriptType`, or put `# IntuneScriptLab: ScriptType=Detection` at the top of the script, and the finding goes away. |
| A rule fires on something Intune tolerates | Every rule cites its `Evidence`, ending in experiment IDs such as `REM-EXIT-2`: those are the experiments in [Experiments.psd1](https://github.com/fadwen/IntuneScriptLab/blob/main/Validation/Experiments.psd1) whose results [Findings.md](https://github.com/fadwen/IntuneScriptLab/blob/main/Validation/Findings.md) summarises. Use `-ExcludeRule` for a deliberate exception, and open an issue with the script if the evidence is wrong. |
| Import fails on Windows PowerShell 5.1 with odd characters in the error | A source file was saved as UTF-8 without a BOM. 5.1 reads that as the ANSI code page. Save with a BOM (this is also what rule `IslEncodingIssue` reports for your scripts). |
| `-Context System` says "run elevated" | `Register-ScheduledTask` needs an administrator session. Restart PowerShell as administrator; the current-user runs need no elevation. |
| `-Architecture x64` refused on an ARM64 PC | ARM64 Windows has no x64 `powershell.exe`; only x86 (emulated) and arm64 (native) exist there, which is what Intune's agent uses too. Test x64 on an x64 machine. |
| Runtime result differs from what Intune showed | Compare what the result carries as Intune reports it: `IntuneOutput` and `IntuneError` on a remediation result, `StdOut`, `StdErr` and `ExitCode` on a detection, platform script or requirement result (OEM code page; the 2,048-character tail where the portal caps it). The `-Verbose` switch prints each step. |
| Pester says `Should-HaveIntuneStatus` is not recognised | The aliases come from this module, not Pester: `Import-Module IntuneScriptLab` in `BeforeAll`, and use Pester 6.2 or later (`New-ShouldAssertion`). |

## Roadmap
- 1.0 once the Gallery release has had a few rounds of real use. Everything on the original list
  shipped: the Graph pre-flight (0.11), the GitHub Actions gate (0.12), suppressions and settings
  (0.13), SARIF (0.14), Repair-IntuneScript (0.15), filters (0.17), another account (0.18), the
  Enrollment Status Page (0.19), drift (0.20), assignment sanity (0.21), the health report (0.22),
  timelines and the diagnostic zip (0.23). See [CHANGELOG.md](CHANGELOG.md).
