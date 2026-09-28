# Security

## Reporting a vulnerability

Please report a vulnerability privately through
[GitHub's private vulnerability reporting](https://github.com/fadwen/IntuneScriptLab/security/advisories/new)
rather than in a public issue. You will get an acknowledgement within a few days and a fix or a
mitigation as soon as one is ready; the report is credited in the release notes unless you ask
otherwise.

## What this module touches

The static analysis (`Test-IntuneScript`, the PSScriptAnalyzer rules) only reads the scripts you
point it at. `Repair-IntuneScript` rewrites them, previews with `-WhatIf`, and never applies a fix
that changes behaviour.

The runtime harness (`Invoke-Intune*Test`) runs the script you give it on this machine, the way
the Intune Management Extension would: it copies the script to a cache folder, launches a
Windows PowerShell host, and kills it at the timeout. With `-Context System` or `-Credential` it
registers a scheduled task to launch under that account and unregisters it when the run ends.
The script itself runs with whatever rights that account has, exactly as it would under Intune;
run scripts you trust.

The Graph pre-flight (`Test-IntuneDeployedScript`, `Compare-IntuneDeployedScript`,
`Get-IntuneScriptHealth`) reads the tenant through the caller's own Microsoft.Graph session. Its
only write is submitting a report export job, which changes nothing in the tenant. If you find a
path by which any command modifies a policy, an app, an assignment or a device, that is a
vulnerability: report it as one.

`Export-IntuneAgentDiagnostic` packs the agent's logs, the enrollment and agent registry keys,
`dsregcmd /status` and the parsed timelines into a zip. That content names the device, the
tenant, the user and every deployed policy. Treat the zip as sensitive and review it before
sharing it.

The validation kit under `Validation/` deploys and removes `ISL-*` objects in a tenant you own and
runs probes on lab devices. Nothing it produces is shipped in the package, and its raw results
are git-ignored because they contain tenant identifiers.

## Credentials

Nothing is stored. A `-Credential` is used once to register the scheduled task and, when the
account has no session, the scheduler holds the password for the life of that task, which is
deleted at the end of the run. The run cache under `ProgramData\IntuneScriptLab\Runs` is granted
to that account for the run and removed afterwards. Graph access is the session you already
opened; the module never prompts for, caches or writes a token.

## Supported versions

Only the latest release on the PowerShell Gallery receives fixes.
