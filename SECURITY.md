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
file you name. `Repair-IntuneScript` rewrites a script only for the three fixes the rules offer:
a UTF-8 BOM, a script-scope `return` rewritten as the `exit 0` Intune already treated it as (with
its value written first), and a padded requirement value trimmed. It previews with `-WhatIf`.

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
the end of the run. The run folder under `ProgramData\IntuneScriptLab\Runs` is granted to that
account for the run and removed afterwards. Graph access is the session you already opened.

## Supported versions

Only the latest release on the PowerShell Gallery receives fixes.
