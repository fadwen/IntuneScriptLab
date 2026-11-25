# Security

## Reporting a vulnerability

Please report a vulnerability privately through
[GitHub's private vulnerability reporting](https://github.com/fadwen/IntuneScriptLab/security/advisories/new)
rather than in a public issue. You will get an acknowledgement within a few days and a fix or a
mitigation as soon as one is ready; the report is credited in the release notes unless you ask
otherwise.

## What this module touches

The static analysis (`Test-IntuneScript`) reads the scripts you point it at and changes nothing.
The PSScriptAnalyzer rules wrapper writes each script's text to a temporary file under the
user's temp folder for the analysis and deletes it. `Export-IntuneFindingSarif` writes the SARIF
file you name. `Repair-IntuneScript` rewrites a script only with the edits that the rules attach
to the findings they report there, each a fixed change at the place the finding names (the README
lists them, from a UTF-8 BOM to `$PSScriptRoot` for `$PWD`). It previews with `-WhatIf`, and
refuses a file whose text does not survive the round trip through its encoding.

The runtime harness (`Invoke-Intune*Test`) runs the script you give it on this machine, the way
the Intune Management Extension would: it copies the script to a run folder, launches a Windows
PowerShell host with `-ExecutionPolicy Bypass`, kills the process tree at the timeout, and
deletes the run folder. `Invoke-IntuneWin32AppTest` runs the install and uninstall commands you
give it the same way, through `cmd.exe`. With `-Context System` or `-Credential` the launch is a
scheduled task registered for the run and unregistered when it ends. The script runs with
whatever rights that account has, exactly as it would under Intune; run scripts you trust.

The Graph pre-flight (`Test-IntuneDeployedScript`, `Compare-IntuneDeployedScript`,
`Get-IntuneScriptHealth`) reads the tenant through the caller's own Microsoft.Graph session; the
module never connects, prompts for or handles a token itself. Its only write to the tenant is
submitting a report export job, which changes nothing there. Locally it writes the tenant's
scripts and the downloaded export to the user's temp folder for the analysis and deletes them.
If you find a path by which any command modifies a policy, an app, an assignment or a device,
that is a vulnerability: report it as one.

`Export-IntuneAgentDiagnostic` packs the agent's logs, four registry keys (the agent's own,
Enrollments, EnrollmentStatusTracking and the Autopilot diagnostics), the system facts,
`dsregcmd /status` and the parsed events and timelines into a zip. That content names the
device, the tenant, the user and every deployed policy. Treat the zip as sensitive and review it
before sharing it.

The validation kit under `Validation/` deploys and removes `ISL-*` objects in a tenant you own and
runs probes on lab devices. Nothing it produces is shipped in the package, and its raw results
are git-ignored because they contain tenant identifiers. Its `New-IslHarnessUser.ps1` does store
a lab account's password on the lab device, DPAPI-protected for SYSTEM and as the LSA autologon
secret; that is a lab device you own, and the script's help says so.

## Credentials

The module stores nothing. A `-Credential` is used to register the scheduled task: when the
account has a signed-in session the task runs interactively in it and no password is passed;
otherwise the password goes to the Task Scheduler for the life of the task, which is deleted at
the end of the run. Each run copies the script to a folder of its own,
`ProgramData\IntuneScriptLabRun-<id>`, created already closed: SYSTEM, the Administrators group
and the user who runs the harness have full control, and no other account can open it. Once the
script is copied in, the run's account is granted Modify on what is in the folder and the rights
to list it and add to it, but not to delete or rename the folder itself, so it cannot redirect the
copy. The name is new for each run, so no other user can take it first, and
a run is refused when something is already there under the name. The folder is removed after the
run. Graph access is the session you already opened.

## Data classification

The controls follow from what each kind of data is (SEC-20). The module handles nothing above
Confidential.

| Data | Classification | Where it goes | How it is handled |
| --- | --- | --- | --- |
| The scripts under test, their findings, and a run's output and exit code | Internal, or Confidential when a script carries a secret | The caller's pipeline; the SARIF file that `Export-IntuneFindingSarif` writes, which holds each finding's path, line and the text of that line | Read where they are; the harness's copy is deleted after the run. The SARIF file is written only where the caller names it. An Intune script often holds a secret, such as an API key or a local account's password; the SARIF snippet of a finding on that line, and a run's output that prints it, then carry it too, so review a SARIF file before uploading it to code scanning. |
| What the tenant commands read from Graph: the deployed scripts, their settings and assignments, and summary counts of their runs and installs | Internal | The caller's pipeline; the Markdown report of `Get-IntuneScriptHealth -MarkdownPath` | Read through the caller's own Graph session. The scripts and the downloaded report export are written to the caller's temp folder for the analysis and deleted. |
| The `-Credential` of a run as another account | Confidential | The Task Scheduler, for the life of the run's task, when the account has no signed-in session | Never written to a file, a stream or an error message. The password is read from the `PSCredential` only in the call that registers the task, and the task is deleted when the run ends. |
| The diagnostic package of `Export-IntuneAgentDiagnostic` | Confidential | The zip the caller names | It names the device, the tenant, the user and every deployed policy. In its list of loaded modules, a folder under the user's Documents or profile is written as `<Documents>` or `%USERPROFILE%`. Review it before sharing it. |
| The validation kit's lab account | Confidential, lab only | The lab device | Not part of the package. `Validation/New-IslHarnessUser.ps1` stores the password of a lab account it creates on a lab device you own, DPAPI-protected for SYSTEM and as the LSA autologon secret. |

## Threats

The threats to the module by STRIDE category (SEC-21), each with the control the module has or
the reason none applies.

| Category | Threat | Control |
| --- | --- | --- |
| Spoofing | A Graph request made under an identity other than the caller's. | The module never signs in, prompts for or holds a token: every request goes through the caller's own Microsoft.Graph session. |
| Spoofing | The download link of a report export, read from Graph's reply, leads to a host that poses as Microsoft's storage. | The link comes from Graph's own reply, which reaches the module over TLS through the caller's session, so another host would need that reply forged. The download carries no credential header and refuses a redirect (`-MaximumRedirection 0`), and the zip is read only as data: the counts in its CSV, with nothing in it run. The module does not check the link's host itself. |
| Tampering | Another local user changes the script copy that a run as another account starts, or the output the harness reads back, in the run folder under ProgramData. | Each run gets its own `ProgramData\IntuneScriptLabRun-<id>`, created with an access list for SYSTEM, the Administrators group, the caller and the run's account only, under a name new for each run; anything already at the name refuses the run (`RunFolderUnsafe`). A run as the current user or as SYSTEM uses the caller's temp folder. |
| Tampering | A policy id or a script name read from the tenant leads a write outside the work folder. | The pre-flight refuses a policy id that is not letters, digits, `_` and `-`, and a script path that resolves outside its work folder (`PolicyIdInvalid`, `PolicyPathOutsideWorkFolder`). |
| Tampering | `Repair-IntuneScript` rewrites a script into something other than what it was. | It makes only the fixed edit that a rule attaches to a finding it reports, at the place the finding names; it previews with `-WhatIf`, and refuses a file whose text does not survive the round trip through its encoding. |
| Repudiation | A change made without a record of who made it. | The module changes nothing outside the files a caller names and its own run folders, and reads the tenant, apart from the report export job, which changes nothing there. It keeps no log of its own; the scheduled tasks it registers are named `IntuneScriptLab-<id>`, so an entry in the Task Scheduler's operational log, where that log is turned on, names the module as their source. |
| Information disclosure | The diagnostic package or a SARIF file leaves the machine. | Both are written only where the caller names them; the package's contents are listed above, with the paths that are written in a general form. |
| Information disclosure | A credential or token reaches a stream, a log or an error message. | No command writes a credential or a token anywhere; errors name the account, never its password. |
| Denial of service | A script under test hangs or never ends. | Every run has a timeout (`-TimeoutSeconds`, 1 to 86,400) after which the process tree is ended and the run reported as timed out. |
| Denial of service | Input long enough to exhaust the analysis. | `-Name`, `-Id`, `-IncludeRule` and `-ExcludeRule` take at most 1,000 characters (`InputTooLong`), and an assignment filter rule at most Intune's own 3,072. |
| Elevation of privilege | A script under test is somebody's code and runs with the rights of the context it is given. | That is the harness's purpose: it runs the script as Intune would, as the caller, or as the account of `-Credential` or as SYSTEM, which needs the right to register a scheduled task for that account; Windows gives that right to an elevated session. The module checks no role: the registration is the test. Run only scripts you trust, and use a lab device or a lab account for the rest. |
| Elevation of privilege | `-ExecutionPolicy Bypass` lets an unsigned script run. | It applies to the one host process the harness starts, as the agent starts it, and changes no policy on the machine. |

## Supported versions

Only the latest release on the PowerShell Gallery receives fixes.
