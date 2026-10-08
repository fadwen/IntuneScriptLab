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

- A Win32 install or uninstall command named as a bare batch file (`install.cmd`) failed with
  "'install.cmd' is not recognized" from `Invoke-IntuneWin32AppTest` on a machine where
  `NoDefaultCurrentDirectoryInExePath` is set in the caller's environment, a per-user shell
  setting that stops `cmd.exe` looking in its working folder. The agent's `cmd.exe` runs without
  the caller's profile, so the harness now starts its child processes without the variable.
- `Invoke-IntuneWin32AppTest` warned about the 32-bit host only when `powershell` appeared on the
  install or uninstall command line. A `powershell.exe` call inside the batch file the command
  line names (`install.cmd`) runs 32-bit just the same, from the agent's 32-bit `cmd.exe`, and now
  gets the same warning, naming the file and line.

## [0.29.0] - 2026-10-07

One finding from a real device, found by running a blog post's example through Intune: a remediation that
writes to stderr is a script error whatever its exit code, and the harness had said Recurred since round 1.
The harness, a rule, the evidence and the help follow the device now.

### Added

- `IslOutputIssue` warns about `Write-Error` and an unguarded cmdlet in a remediation script, the way it did
  for Win32 detection scripts, since either makes the agent report a script error instead of running the
  post-detection; the unguarded cmdlet carries `-ErrorAction Stop` as its fix.

### Fixed

- **`Invoke-IntuneRemediationTest` reported Recurred for a remediation that writes to stderr and exits 0.** On
  the device that run is a script error: `RemediationStatus` 3, Graph `remediationState` `scriptError`, the
  error text attached, no post-detection. The harness now reports Failed, skips the post-detection and warns
  that the exit code was 0. A detection that writes to stderr and exits 0 is still Without issues, as before.
  Measured in user context on the lab device with five one-off remediations (round 11, `REM-STDERR-*`).
## [0.28.0] - 2026-10-06

Two commands run several times faster, the fixer applies eight more edits, the Graph calls are retried
and judge a device group by its whole membership, three harness commands take the pipeline, and two
tables the rules report from are held against real hosts by tests. The first items are the slow ones
found by measuring; the lab device was started once, to re-capture the in-box module list.

### Added

- `Invoke-IntuneDetectionTest`, `Invoke-IntunePlatformScriptTest` and `Invoke-IntuneRequirementTest` take script
  paths from the pipeline, by value or from a `FullName` or `PSPath` property, so `Get-ChildItem .\Detections |
  Invoke-IntuneDetectionTest` runs each one. `Test-IntuneWin32Rule`, `Test-IntuneWin32Requirement` and
  `Export-IntuneAgentDiagnostic` results have a format view, like every other result type; the module contract
  test now requires one for every output type an exported command declares.

- `Repair-IntuneScript` applies eight more edits, each the one the finding's message asks for: `-Force` on
  `Install-Module`, `Install-PackageProvider`, `Install-Package`, `Update-Module` and `Uninstall-Module`,
  `-Confirm:$false` on `Register-PSRepository`, `-ErrorAction SilentlyContinue` on a probing cmdlet in a Win32
  detection or requirement script, `exit 1` for an exit code other than 0 or 1, `$env:ProgramW6432` for
  `$env:ProgramFiles`, `'ARM64|AMD64'` for `'AMD64'` as a `-match` pattern, `$PSScriptRoot` for `$PWD`, a
  `Get-Credential -Credential` call handed a credential that can only be one already built replaced by that
  credential, and a `Set-ExecutionPolicy` statement or a `#Requires -Version 7` line removed. An edit that
  would leave a broken statement is withheld and the finding stays: `Set-ExecutionPolicy` in a pipeline,
  `'AMD64'` compared with `-eq`, `$PWD.Path`. The `#Requires` finding now sits on its line rather than on
  the whole script.

### Changed

- CI: the Windows PowerShell 5.1 job runs the integration suite as well as the unit suites, so a 5.1 trap in the
  harness fails a pull request rather than a device run. Every test job writes its results as NUnit XML and the
  pwsh job its coverage as JaCoCo XML, uploaded as artifacts whether the job passes or fails.

- The in-box module table `IslModuleDependency` reports from is held against the Windows client the tests run
  on: every listed module must be under the host's system module paths, except the engine module and the seven
  a Home edition lacks, and nothing may be under the Windows module folder that the table or the test does not
  account for, Hyper-V and the container family being features a host may have turned on. The table
  was re-captured as SYSTEM on the lab device on 2026-10-06 and is unchanged.

- Validation kit: `Collect` moves its payload through the guest agent's file-read call in one
  reply, gzipped on the device before base64, instead of 179 guest exec calls of 100,000
  characters; scripts go in through the agent's file-write call, 30,000 characters per call
  instead of 1,200 (`Send-GuestFile`, `Receive-GuestFile` in `GuestAgent.ps1`). `Collect -Since`
  keeps only the probe records written from that time on. The round-7 experiment
  `REM-INSTALL-MODULE`, which hangs for its 60-minute timeout every hour and holds the lab's
  remediation runner, is no longer assigned.

- The cmdlets, parameters and values `IslPowerShell7Syntax` reports are one table
  (`Get-IslCoreOnlyFeature`), and a unit test holds every entry against both hosts as child
  processes: absent from Windows PowerShell 5.1, present in PowerShell 7, a value refused by the
  5.1 `ValidateSet` and taken by 7. The three entries above are what it found on its first run.

- `IslInteractiveCall` tells a `Get-Credential -Credential` call that cannot prompt from one that may:
  when every value the argument can hold is a credential, built by `[pscredential]::new()`, `New-Object`,
  `Import-Clixml`, a cast or a `[pscredential]` parameter, the finding is a note that says the call can go.
  A variable with any other source, a member or a call stays a warning.

- The release rehearsal (`Build/Publish-Module.ps1 -WhatIf`) measures the manifest's `Description` and the
  package's tags against the Gallery's 4,000-character limits, next to the `ReleaseNotes` check from 0.27.0.
  The tags counted are the ones the Gallery lists, the manifest's plus `PSModule`, the editions and two per
  exported command, so a new command costs about twice its name. The module contract test holds the same
  three limits, so a pull request fails before a release does.

- `Test-IntuneScript` runs about two and a half times faster: 91 ms a script against 233 ms for a 95-line
  detection, 60 scripts in 5.4 s against 14.0 s. Every rule walked the syntax tree itself, some once per
  command name they look for; the tree is now walked once per script and the nodes indexed by type and
  the commands by name, and the rules read the index. Findings are unchanged.

- `Get-IntuneAgentLog` and `Get-IntuneAgentTimeline` read a large log in a fraction of the time. On a 15 MB
  agent log of 80,000 entries: every entry in 30 s against 62 s; the entries of one policy, by `-Id`, in
  5 s against 25 s; `-EventName` with `-Last` in 12 s against 90 s; a timeline by id in 5 s against 26 s.
  The filters now run on the raw record before an entry is built, which was most of an entry's cost; the
  44 event patterns are one expression matched once per message instead of 44 statements; a rolled-over
  file last written before `-After` is not read at all. Results are unchanged.

- Every Graph request the tenant commands make is sent again when Graph throttles it (429) or is briefly
  unavailable (503, 504): after the `Retry-After` seconds when the header is there, after 2, 4 and 8 seconds
  when it is not, three times at most before the failure is thrown as it came. A pre-flight over a few hundred
  policies makes two requests per policy and meets the throttle.

### Fixed

- **`Test-IntuneDeployedScript` decided whether a group holds devices from its first 20 members.** A mixed group
  whose first page was all devices passed as a device group, and a user-context app assigned to it was flagged
  as never installing. The check now counts the group's members and the devices among them with two `$count`
  queries, so the whole group decides.

- **`Repair-IntuneScript` analyzed every script under the inferred context and architecture**, whatever the
  caller deployed to, because it had no `-Context`, `-Architecture` or `-EnforceSignatureCheck` to pass on.
  It takes the three now and hands them to both analyses, so its findings, fixes and `Remaining` count are
  the ones `Test-IntuneScript` gives for the same options.

- **`-Credential` found no session on Windows Home editions, and matched by name.** The session
  list came from parsing `query user`, which Home editions do not ship (every run there fell back
  to the stored-password task) and which prints localized text. Sessions now come from the owners
  of each desktop's `explorer.exe` and `sihost.exe` through CIM, and the account is matched by
  its SID when Windows resolves the credential's name, by the owner's name otherwise. Verified on
  this Home machine and on the joined lab device with the Entra user signed in.

- **The stored-password task was registered with the credential's name as given**, which the
  scheduler refuses for an Entra account's sign-in name ("No mapping between account names and
  security IDs"). It is registered for the name Windows gives the account. On the lab device such
  a task then never starts for an Entra account, with or without the "Log on as a batch job"
  right, so the refusal names that instead of the right.

- **`IslPowerShell7Syntax` listed three things that are not PowerShell 7-only.** `Switch-Process`
  exists on Linux and macOS only, so a script calling it fails on both Windows hosts;
  `Invoke-WebRequest -StatusCodeVariable` exists on neither host (only `Invoke-RestMethod` has
  it); `Get-ChildItem -FollowSymlink` has been in Windows PowerShell since 5.0. All three are
  gone from the rule.
## [0.27.0] - 2026-10-05

Fixes to the runtime harness and to four rules, each rule change backed by a tenth validation
round on the lab device. No command changes shape.

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
- **`-Credential` did not find a Microsoft Entra account's session.** The launcher looked for
  the credential's user name, taken apart as text, in `query user`. Windows calls an Entra
  account `AzureAD\<display name without spaces, cut at 20 characters>`, which is neither the
  sign-in name nor a part of it, so a credential naming `user@domain` was refused ("No mapping
  between account names and security IDs") or fell back to the stored-password task. The
  launcher now asks Windows which account the credential means, finds the session by the name
  Windows gives it, registers the interactive task for that name and grants the run folder by
  SID. Verified on the joined lab device with the sign-in name, `AzureAD\<sign-in name>` and
  the Windows name (Findings, "The harness as another account").
- Under `-ErrorAction Stop` on Windows PowerShell 5.1, a refused grant on the run folder ended
  with `icacls`' bare line ("No mapping between account names and security IDs was done")
  instead of the message naming the account and the folder.
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
- The manifest's `ReleaseNotes` keeps the newest three versions and points at this file for the
  rest. The Gallery refused the first 0.27.0 upload with a 400: the notes, every version since
  0.1.0, had passed its 10,600-character limit, and nothing local measured them. The release
  rehearsal (`Build/Publish-Module.ps1 -WhatIf`) now does.

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

[Unreleased]: https://github.com/fadwen/IntuneScriptLab/compare/v0.29.0...HEAD
[0.29.0]: https://github.com/fadwen/IntuneScriptLab/compare/v0.28.0...v0.29.0
[0.28.0]: https://github.com/fadwen/IntuneScriptLab/compare/v0.27.0...v0.28.0
[0.27.0]: https://github.com/fadwen/IntuneScriptLab/compare/v0.26.0...v0.27.0
[0.26.0]: https://github.com/fadwen/IntuneScriptLab/compare/v0.25.0...v0.26.0
[0.25.0]: https://github.com/fadwen/IntuneScriptLab/releases/tag/v0.25.0
