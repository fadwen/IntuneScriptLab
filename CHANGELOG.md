# Changelog

All notable changes to this module are recorded here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Versions before 0.25.0 were released from the
[powershell_scripts](https://github.com/fadwen/powershell_scripts) repository, where the module
lived under `Scripts/Intune/IntuneScriptLab`. Their entries are carried over from the manifest's
release notes.

## [Unreleased]

### Fixed

- **A user-context run started from PowerShell 7 loaded PowerShell 7's modules.** The 5.1 host
  inherited the session's `PSModulePath` and took `Microsoft.PowerShell.Management`, `Utility`
  and `Security` from PowerShell 7's folders: no `Cert:` drive, and `Get-AuthenticodeSignature`
  and `ConvertTo-SecureString` failed to load, so a script that works under the agent failed in
  the harness. The child now gets the session's path without the three folders PowerShell 7
  adds for itself. Runs started from Windows PowerShell, and the scheduled-task runs (SYSTEM,
  `-Credential`), are unchanged.
- A backtick line continuation in `Get-IslSetting`, the one left in the module since 0.6.0 said
  there were none.
- **`Repair-IntuneScript` hid the mistake it was run on.** `return 1; exit 1` became
  `1; exit 0; exit 1`: the same behaviour, the exit the author wrote unreachable, and no finding
  left. A script-scope `return` with an exit other than 0 after it in the same block now carries
  no edit and stays reported; a `return` with nothing, or `exit 0`, after it is fixed as before.
- **`IslPowerShell7Syntax` gave the parse error's evidence for errors that are not parse errors.**
  A cmdlet or parameter only PowerShell 7 has, and `ForEach-Object -Parallel`, parse under 5.1:
  the call fails, the script carries on and a detection reaches its own exit 0, the opposite of
  the exit 1 the evidence described. The messages say so and cite the new experiments
  (REM-PS7-CMDLET, REM-PS7-PARAM, REM-PS7-PARALLEL); `#Requires -Version 7` cites its own
  (REM-PS7-REQUIRES).
- **`Out-File -Encoding utf8NoBOM` was in the rule's table and never matched**, filtered out by
  the code that read the table. It is a finding now, with what the agent did with it
  (REM-PS7-ENCODING). An empty `Rename-Item` entry is gone.
- **`IslInteractiveCall` called `Get-Credential -Credential $credential` an error**, although a
  credential that is already built is returned without a prompt (12 ms under the agent,
  REM-CRED-BUILT). It stays an error where it is sure to prompt (bare, with `-Message` or
  `-UserName`, or handed a literal name) and is a warning when handed anything else.

### Changed

- `IslContextIssue` reported every path from `D:\` to `Z:\` in a SYSTEM script as an unmapped
  drive, a warning. A SYSTEM detection saw a local `D:` and not the `X:` the signed-in user had
  mapped (REM-DRIVES-SYS), and the letter cannot say which of the two a script means, so the
  finding is now Information and says which case fails.
- Validation round 10 (Findings, "PowerShell 7 at run time, a built credential, and the drives
  SYSTEM sees"): seven remediations on the joined device, and `New-IslDriveFixture.ps1` in the kit
  for the drive state one of them reports on.
- Validation kit: `Collect` failed on a device payload in which one chunk had arrived as another
  chunk's text. The QEMU guest agent answers a status call with the oldest result it holds for a
  process id, and Windows reuses the ids. `GuestAgent.ps1` now carries the guest calls for the
  driver and `Invoke-LabGuestScript.ps1`: every command prints a marker of its own, a result
  without it is passed over, a result lost to a timed-out status call makes the command run
  again, and the payload is checked against the device's SHA-256.
- The README and `Get-IntuneAnalyzerRulePath`'s help say what `Invoke-ScriptAnalyzer -Severity`
  does with the custom rules: PSScriptAnalyzer 1.25.0 filters on the rule's registered severity,
  Warning for every custom rule, so `-Severity Error` returns none of the records and
  `-Severity Warning` all of them. They also describe the cache as it works: nested script
  blocks are skipped, and the cache serves the other rules at the root.
- The about topic named "a missing exit" among `Repair-IntuneScript`'s fixes; they are a
  script-scope return, the encoding and a padded requirement value.

## [0.26.0] - 2026-09-28

Every claim the module makes, in its README, help, about topic, rule reference, examples and
changelog, was checked against the code and by running it. What follows is what did not hold.

### Fixed

- **`-Settings` never reached the analysis.** `Test-IntuneDeployedScript` and
  `Compare-IntuneDeployedScript` overwrote their `Settings` parameter with a body-level
  `$settings` hashtable (variable names are case-insensitive) and then tested
  `$PSBoundParameters` inside a nested function, where it is that function's own. The
  pre-flight ran its normal settings-file search instead, and the drift compare ignored the
  hashtable. `Get-IntuneScriptHealth` forwarded the parameter to both, so it lost it too.
- **`-Id` on its own selected every policy** in the three Graph commands, because `-Name`
  defaults to `*` and selection was name or id. `-Id` alone now selects by id.
- **`Repair-IntuneScript -Path <folder> -WhatIf` returned nothing.** The folder was enumerated
  through `ForEach-Object -MemberName`, which honours `-WhatIf`. `Test-IntuneScript` had the
  same construct and returned no findings for a folder while `$WhatIfPreference` was set.
- **The encoding fix corrupted ANSI files.** A BOM-less file that was not UTF-8 was decoded as
  UTF-8 and written back with every non-ASCII character replaced by U+FFFD. Repair now reads
  such a file in the system ANSI code page, and `IslEncodingIssue` reports it as ANSI
  (Information) rather than as UTF-8 without a BOM.
- **A type declared in a directive earned the assumed-context note** and was called a portal
  default. A directive is a declaration; the note is for inferred types only.
- **A settings file's `ExcludeRule` beat an explicit `-IncludeRule`.** An explicit include now
  sets the file's exclusions aside; `-ExcludeRule` still adds to them.
- **`Should-PassIntuneAnalysis` failed on a pipeline of files**, joining their paths into one.
  It now analyzes every file and names the ones that fail.
- **SARIF:** every rule was given the level `warning`; it now carries the level of the most
  severe finding it produced in the log. A finding outside `-Root` was written as an escaped
  relative URI under the root; it is now an absolute file URI. A relative `-Path` was resolved
  against the process directory, as was `Get-IntuneScriptHealth -MarkdownPath`.
- **A missing script path** made the harness return a result with a made-up exit code instead
  of an error.
- **`Get-IntuneAgentTimeline -Id`** returned every timeline whose lines mentioned the id (a
  relationship report names two apps); it now returns the timeline whose own id it is. A
  relationship report is an outcome.
- **`Compare-IntuneDeployedScript`** compared content without regard to case, so a change in
  letter case only came back as "the bytes differ outside the UTF-8 text".
- **A user-context Win32 app assigned to All devices** was not flagged, only one assigned to a
  device group.
- **`Get-IntuneScriptHealth -SkipAnalysis`** called an unassigned policy Healthy, because the
  check read a finding. It now reads the assignments.
- **`IslFilterIssue`** called `-ne` and `-notIn` with a value no device reports "never matches";
  such a clause matches every device, and is reported so, as Information.
- **`IslInteractiveCall`** took a bare `-Confirm`, which forces the prompt, as silencing it.
- **`IslOutputIssue`** took `$ErrorActionPreference = 'Stop'` as guarding a probing cmdlet;
  Stop puts the miss on stderr, which is the failure the rule warns about.
- **`IslPowerShell7Syntax`** reported a `using module` the parser could not find as PowerShell 7
  syntax, and listed `Get-Process -CommandLine` and `New-TemporaryFile -Extension`, which exist
  on neither host.
- **`IslScriptSize`** called Win32 detection and requirement scripts remediations; it now names
  them and says the remediation limits are assumed for them, since only remediations and
  platform scripts were measured.
- **A stored-password task the scheduler never launches** made the harness wait out the whole
  timeout. For an account without the "Log on as a batch job" right the lab device no longer
  answers `0x80070569`; the task sits Ready with `0x00041303` ("has not run yet") and no error
  anywhere. Five seconds of that is now reported as the refusal, with the same hint.
- **`Test-IntuneScript -EnforceSignatureCheck:$false`** was not explicit, so a tenant script's
  own directive could turn the check on under the pre-flight.
- A typo in the `IslContextIssue` message; the AgentTimeline `Duration` column dropped days;
  the workflow template's runtime job did not split a comma-separated `SCRIPT_PATHS`.

### Changed

- The reporting lag in `Get-IntuneScriptHealth`'s help is the measured one: a remediation's
  changed result reaches Graph with the agent's next hourly report batch (65 minutes after the
  run on 2026-09-29), a platform script's in 2-8 s, an app's in 30-39 s; an unchanged result is
  not re-reported, so `lastStateUpdateDateTime` is the last change. `Get-IntuneAgentTimeline`'s
  help gave the remediation report codes wrong: 3 is no issue, 4 is the remediation having run
  (fixed or not), 5 is a detection script failure.
- The rule reference keeps literal names such as `$PSScriptRoot` in a message instead of
  replacing them with `<value>`.
- The manifest description names the whole module; the README's links into the repository are
  absolute, since the README ships in the package and `docs/` and `Validation/` do not.
- Help corrections throughout: what each result carries (`RunAs`, `IntuneError` as the stderr
  tail, `SignatureStatus` always present), the complete status lists, the events
  `Get-IntuneAgentLog` names, the Id rule, what `-SkipRegistry` leaves out, the ARM64 note on
  the x64 default, the base requirements `Test-IntuneWin32Requirement` covers, how names are
  matched and which local files count as `NotInTenant`, the Attention rules, and the
  `Applied` count under `-WhatIf`.

## [0.25.0] - 2026-09-28

The first release from this repository, and the first published to the PowerShell Gallery.
Nothing any command does has changed.

### Added

- **Build and release tooling.** `Build/Build-Help.ps1` gained `-ValidateOnly` for the pull
  request gate; `Build/Publish-Module.ps1` stages an allowlist of shipping files, proves the
  staged copy imports, analyzes a sample detection script, ships its PSScriptAnalyzer rules and
  serves its help, and publishes. Releases run from a `v*` tag through
  `.github/workflows/release.yml`.
- **CI** runs PSScriptAnalyzer and the 115-character line limit, the suites shuffled with an 80%
  coverage gate on PowerShell 7, the unit suites on Windows PowerShell 5.1 and on Windows on
  ARM, and on Linux fails when the help Markdown is invalid, the committed MAML or rule
  reference is stale, or `Get-Help` is not served on a case-sensitive filesystem.
- **`Get-Help <command> -Online`** opens the command's Markdown page on GitHub: every help file
  carries its `HelpUri` and the compiled MAML lists it as the Online Version.
- `CHANGELOG.md`, `LICENSE` and the mirrored PowerShell standards.

### Changed

- The build scripts moved from the module root to `Build/`; the manifest's project and license
  URIs point at this repository, and the README installs from the Gallery.

## [0.24.0] - 2026-09-28

### Added

- `about_IntuneScriptLab` (`Get-Help about_IntuneScriptLab`) explains the evidence model, the
  script types and every command.
- `docs/Rules.md` is generated from the rule files by `Build-RuleReference.ps1`, one row per
  finding with its evidence and experiment ids, and a unit test keeps it current.

### Changed

- The validation kit's scripts no longer use backtick line continuations.

## [0.23.0] - 2026-09-28

### Added

- `Get-IntuneAgentTimeline` tells one policy's or app's story from the named log lines: steps,
  duration, launches, last result.
- `Export-IntuneAgentDiagnostic` packs the logs, the registry state, the device facts and the
  parsed events and timelines into one zip.
- The event table gains the relationship lines: `AppSubgraph`, `AppSubgraphSkipped`,
  `AppRelationshipReport`, `AppDependencyToast`, `AppNoIntent`, `AppDownload`.

### Fixed

- `Get-IntuneAgentLog` takes the first non-empty GUID as the id, so a userless check-in no
  longer hides the policy id.

## [0.22.0] - 2026-09-28

### Added

- `Get-IntuneScriptHealth` puts the findings, the drift, the assignment and what the devices
  reported (remediation and platform script run summaries, app install counts from the
  `AppInstallStatusAggregate` export) on one line per policy with a Health verdict and its
  reasons, and writes the same as Markdown with `-MarkdownPath`.

## [0.21.0] - 2026-09-28

### Added

- Assignment sanity (validation round 9): `Test-IntuneDeployedScript` warns about a policy with
  no assignment or only exclusions (never resolved by any device), notes a run-once schedule
  whose time has passed (runs once at the fetch on a device that has not run it) and a
  user-context script assigned to devices (skipped on Entra registered devices).
- `Validation/Invoke-AssignmentProbe.ps1` creates the round's policies.

## [0.20.0] - 2026-09-28

### Added

- `Compare-IntuneDeployedScript` compares every script a tenant's remediations, platform scripts
  and Win32 apps carry with its local copy byte for byte (found by convention under `-Path` or
  named through `-Map`), reporting the BOM, line endings, whitespace and content apart, a
  directive or settings file against the policy's run-as, bitness and signature check, and
  policies without a local file, ambiguous matches and local files the tenant has no script for
  as states of their own.

## [0.19.0] - 2026-09-28

### Added

- The Enrollment Status Page: `Get-IntuneAgentLog` names the page's phases, selected apps,
  registrations, tracked install states and completion (`ScriptEspPhase`, `EspPhase`,
  `EspAppsSelected`, `EspAppRegistered`, `EspAppState`, `EspPhaseComplete`, `EspComplete`,
  `EspNontrackedCheckin`, `UserlessCheckin`), from an Autopilot run recorded in Findings.
- The platform-script and remediation help say where each script type runs relative to the page.
- `Validation/Get-IslEspEvidence.ps1` collects the evidence from a lab device.

## [0.18.1] - 2026-09-27

### Fixed

- Verified on the lab device: the interactive task reproduces the agent's user-context launch; a
  stored-password task the scheduler refuses (`0x80070569`, no "Log on as a batch job" right)
  is reported at once instead of at the timeout.

## [0.18.0] - 2026-09-27

### Added

- `-Credential` on the five `Invoke-Intune*Test` commands runs the script as that account
  through a scheduled task, in the account's own session when it has one (the way the agent
  runs user-context scripts as the signed-in user) or with a stored-password logon in session 0
  otherwise; results carry `RunAs`.
- `Validation/New-IslHarnessUser.ps1` creates the lab account.

## [0.17.0] - 2026-09-27

### Added

- `Test-IntuneAssignmentFilter` parses a filter rule the way the service's `validateFilter`
  accepts and refuses it and evaluates it against this device or a described one with the
  matching the service's filter evaluator showed (case-insensitive, trimmed values, `and`
  before `or`, numeric versions, a missing value as empty).
- `Test-IntuneDeployedScript` reads the filter on every assignment and flags a clause no Windows
  device can match (`IslFilterIssue`).

## [0.16.0] - 2026-09-27

### Added

- Three rules from a seventh validation round: `IslExecutionPolicyCall` (the agent launches with
  Bypass), `IslModuleDependency` (modules outside the SYSTEM session's in-box list, and gallery
  installs inside a script) and `IslScriptSize` (the documented 200 KB against what the service
  accepts and refuses).

## [0.15.0] - 2026-09-27

### Added

- `Repair-IntuneScript` applies the mechanical, behaviour-preserving fixes: a script-scope
  `return` becomes the `exit 0` it implied (with its value written first), a UTF-16 or BOM-less
  non-ASCII file becomes UTF-8 with a BOM, a padded requirement value is trimmed; findings carry
  the edit as `Fix`, and `-WhatIf` previews.

## [0.14.0] - 2026-09-27

### Added

- `Export-IntuneFindingSarif` writes findings as a SARIF 2.1.0 log (rule entries from the rules'
  help, relative paths, in-source suppressions); the CI gate takes `-SarifPath` and the workflow
  template uploads it to code scanning on request.

## [0.13.0] - 2026-09-27

### Added

- `Suppress=Rule` in the directive comment silences a rule for the file, the next line or its
  own line (`Test-IntuneScript -IncludeSuppressed` shows them; findings carry `Suppressed`).
- `IntuneScriptLab.settings.psd1` next to the scripts sets exclusions, severity overrides and
  the default type, context, architecture and signature check, below parameters and directives;
  `-Settings` on `Test-IntuneScript`, `Test-IntuneDeployedScript` and the CI gate.

## [0.12.0] - 2026-09-27

### Added

- `Examples/Invoke-IntuneScriptGate.ps1` runs the analysis for a build with GitHub annotations, a
  job summary and an exit code at a chosen severity; `Examples/intune-script-gate.yml` is the
  workflow to copy into a repository of Intune scripts.

## [0.11.0] - 2026-09-27

### Added

- `Test-IntuneDeployedScript` reads the tenant's remediations, platform scripts and Win32 apps
  through the caller's Microsoft.Graph session and runs the rules on every script with the
  policy's own run-as, bitness and signature settings, plus the file `doesNotExist` rule, the
  user-context app on a device group and the detect-only remediation.

## [0.10.0] - 2026-09-27

### Added

- The analysis as PSScriptAnalyzer custom rules (`PSScriptAnalyzer/IntuneScriptLab.Rules.psm1`,
  one `Measure-Isl*` function per rule) for `Invoke-ScriptAnalyzer -CustomRulePath`, with
  `Get-IntuneAnalyzerRulePath` for the path.
- The daily remediation observed over four days, and the drift of the hourly schedule.

## [0.9.0] - 2026-09-25

### Added

- `Get-IntuneAgentLog`: the agent's four CMTrace logs as objects, merged in time order, with the
  events the validation rounds identified (policy fetches, remediation schedule, start and
  verdict, Win32 applicability, detection, rule evaluation, install and report, AgentExecutor
  exit codes and output) and filters by log, id, event, level, time and pattern.

## [0.8.0] - 2026-09-25

### Added

- `-DependsOn` and `-Supersedes` on `Invoke-IntuneWin32AppTest` run the child-first install, the
  detect-only block and the replace uninstall the way the agent was observed to.

### Changed

- A detect-only remediation is one created without a remediation script, not an assignment
  setting.

## [0.7.0] - 2026-09-24

### Added

- `Test-IntuneWin32Requirement` with the observed applicability texts and codes;
  `-InstallContext` on `Invoke-IntuneWin32AppTest`; the 8-hour script policy cadence; from a
  round of tenant experiments on requirements, filters, dependencies, supersedence and MSI
  packages.

## [0.6.0] - 2026-09-24

### Added

- Win32 file, registry and MSI rules: `Test-IntuneWin32Rule`, multi-rule detection and an
  uninstall flow in `Invoke-IntuneWin32AppTest`, the enforced signature check on detection
  (`-EnforceSignatureCheck`, `IslSignatureIssue`), the platform-script retry limit, all from a
  round of tenant experiments.

### Changed

- No backtick line continuations anywhere in the module.

## [0.5.0] - 2026-09-23

### Added

- Win32 requirement rules: `Invoke-IntuneRequirementTest`, `Should-BeIntuneApplicable`,
  `Should-NotBeIntuneApplicable` and requirement checks in `IslOutputIssue`, from a round of
  tenant experiments; folder-aware type inference; PlatyPS help.

### Changed

- Harness `-Context` value `User` (was `CurrentUser`).

## [0.4.0] - 2026-09-23

### Added

- Pester 6.2 assertions: `Should-HaveIntuneStatus`, `Should-BeIntuneDetected`,
  `Should-NotBeIntuneDetected`, `Should-HaveIntuneRunState`, `Should-PassIntuneAnalysis`; a test
  suite template.

## [0.3.0] - 2026-09-23

### Added

- SYSTEM context via scheduled task; `Invoke-IntuneWin32AppTest` (detect, install, detect).

## [0.2.0] - 2026-09-23

### Added

- Runtime harness (current user) with x86/x64/arm64 host switching.

## [0.1.0] - 2026-09-23

### Added

- Static rules: `Test-IntuneScript`.

[Unreleased]: https://github.com/fadwen/IntuneScriptLab/compare/v0.26.0...HEAD
[0.26.0]: https://github.com/fadwen/IntuneScriptLab/compare/v0.25.0...v0.26.0
[0.25.0]: https://github.com/fadwen/IntuneScriptLab/releases/tag/v0.25.0
