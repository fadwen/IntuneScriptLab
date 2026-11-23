# IntuneScriptLab

Tests Intune PowerShell scripts before Intune does: static rules for remediation, platform and
Win32 scripts, a runtime harness that launches them the way the Intune Management Extension does,
Pester assertions, a Graph pre-flight over the tenant's deployed scripts, and readers for the
agent's logs. Published to the PowerShell Gallery.

## Where the conventions live

General PowerShell conventions - module structure, help, Pester, PlatyPS, error handling - come
from [ai-powershell-standards](https://github.com/fadwen/ai-powershell-standards). Its installer
writes them into this repository, and `.github/workflows/sync-copilot-standards.yml` runs it every
week and opens a pull request when they change:

- `.github/copilot-instructions.md` and `AGENTS.md`
- `.github/instructions/powershell-*.instructions.md`
- `.github/instructions/pester-supporting-docs/`
- `.claude/rules/powershell-standards/`
- the `powershell-*` skills under `.github/skills/`, `.claude/skills/` and `.agents/skills/`

**The next sync overwrites those files.** A local edit there is silently reverted, and a file the
standards stop producing is deleted. Changes belong upstream in the standards repository.

This file is not one of them, so it is the right place for anything specific to this module.
What follows is *not* general convention - it is the set of local invariants that look wrong or
arbitrary until you know why, and that are cheap to break by accident.

## Invariants

### Every rule and verdict is backed by evidence, and the evidence is in `Validation/`

A rule fires because a device did something, not because a document says it would. Each finding
carries `Evidence` ending in experiment ids such as `REM-EXIT-2`; those are entries in
`Validation/Experiments.psd1` whose results `Validation/Findings.md` records round by round. A new
rule needs a new experiment and a Findings entry, or it is a guess dressed as a finding. When a
rule and the docs disagree, the rule follows the device and the Findings entry says so.

### The validation kit is not shipped and needs a lab

`Validation/` runs experiments against a real tenant (through the caller's Microsoft.Graph
session) and real devices (Proxmox guests driven through `Invoke-LabGuestScript.ps1`). It is in
the repository because the evidence has to be reproducible, and out of the package because an
installed user has no use for it. `Validation/Results/` and `Validation/Tools/` are git-ignored:
raw results name the tenant's users and devices, and Tools holds a downloaded Microsoft binary.
Only `Validation/Tests/Unit` runs in CI.

### `docs/Rules.md` is generated and a test keeps it current

`Build/Build-RuleReference.ps1` folds every rule's finding hashtables out of the AST and writes
one row per finding with its evidence. `Tests/Unit/RuleReference.Tests.ps1` regenerates and
compares, so a changed message, severity or evidence string fails the suite until the file is
rebuilt and committed. Never edit `docs/Rules.md` by hand.

### A new command goes in four places

`FunctionsToExport` in the manifest, the explicit `Export-ModuleMember` list at the end of
`IntuneScriptLab.psm1`, the export list in `Tests/Unit/Module.Contract.Tests.ps1`, and the help
Markdown under `docs/IntuneScriptLab/`. Missing the second is the one that bites: the manifest
declares it, the contract test expects it, and the command is still not exported.

### Windows PowerShell 5.1 is a real target, and the tests are Windows-only

The manifest declares `CompatiblePSEditions = Desktop, Core` and the root module carries
`#Requires -Version 5.1`, because the agent runs scripts with 5.1 and so do the harness hosts.
A ternary, `??`, `ForEach-Object -Parallel` or `Join-Path` with more than one child path parses on
7 and breaks every command on 5.1. Two 5.1 traps the suites already hit: `Group-Object` orders
groups differently (sort explicitly), and .NET Framework's `ZipFile::CreateFromDirectory` writes
backslash entry names (build zips entry by entry with forward slashes).

The harness launches `powershell.exe` hosts by architecture, reads the registry and registers
scheduled tasks, so the suites run on Windows only: the `desktop` job under 5.1 and the `arm64`
job on Windows on ARM. The `help` job proves the module imports on Linux and that
`Test-IntuneScript` analyzes a folder there, with the script type inferred from forward-slash
paths; no suite and no harness run there.

### Variable names are case-insensitive, and nested functions have their own `$PSBoundParameters`

A body-level `$settings = @{ ... }` silently overwrote the `-Settings` parameter of two commands,
and `$PSBoundParameters.ContainsKey('Settings')` inside a nested helper was the helper's own,
always false. Name locals so they cannot collide with a parameter, and capture what a nested
function needs from `$PSBoundParameters` into a plain variable before defining it. 0.26.0 fixed
both, with tests.

### The module runs under strict mode, and optional members are read through one accessor

`IntuneScriptLab.psm1` sets `Set-StrictMode -Version Latest`, so in every function a read of a
member that is not there is a terminating error: `$reply.runSchedule` on a Graph reply without a
schedule, `$table.Severity` on a settings table without that key, `$result.Sid` on a CIM call that
returned nothing. A hashtable the module's own caller wrote is read with an index
(`$Rule['Operator']`), which gives `$null` for a missing key. Everything that comes from outside -
a Graph reply, an export row, a CIM result, an object that has one of two shapes - is read with
`Get-IslPropertyValue`, which returns nothing for a missing input, key or property and works for a
dictionary and an object alike. `Invoke-MgGraphRequest` returns dictionaries and a recorded fixture
read with `ConvertFrom-Json` returns objects, so member syntax that passes against one can fail
against the other.

Code inside `InModuleScope` runs under the module's strict mode too. A mock body does not: it
stays in the test file's scope, where it can also call the helpers in `Tests/TestHelpers`. A fake
of a run result goes through `ConvertTo-FakeRunResult`, so that it has every member the real one
has.

The loader fails the import when `Private`, `Private/Rules` or `Public` is missing or a file in
them fails to load. A file that does not parse used to leave the module imported without its
commands.

### A call to a function that can fail sits inside `try` with a `catch`

A function that ends with `$PSCmdlet.ThrowTerminatingError()` ends only itself. The module function
that called it carries on at its next statement with nothing where the result should be, unless the
call is inside a `try` that has a `catch`; a `try` with only a `finally`, a nested helper and a
pipeline do not stop it. A `throw` ended every function above it, which is what the callers were
written for. The module is moving from `throw` to `ThrowTerminatingError` one area at a time (#64),
callers first: the caller gets `try { ... } catch { $PSCmdlet.ThrowTerminatingError($_) }`, then the
function it calls is converted.

`Tests/Unit/Module.ErrorFlow.Tests.ps1` holds the rule on the syntax trees, because behaviour does
not show it: a caller that goes on with nothing often returns nothing too, and `Should-Throw` calls
inside a `try`, where every error travels all the way up. The test lists the calls that still rely
on a `throw`, and the list must match the code exactly. `Invoke-CallerScript` in the test helpers
runs statements from a script without `try` in a new process, for what such a caller sees.

A failure the module detects itself is raised with a record from `New-IslErrorRecord`, which gives
it an ID and a category. That function must not fail: it is called in the argument of
`ThrowTerminatingError`, and an error there would end only that statement.

### A nested function returning `@()` hands the caller `$null`

Several public commands use nested helper functions. PowerShell unrolls an empty array on the
way out, so a `[object[]]` parameter splatted from that result binds `$null` and fails. Wrap with
`@($x | Where-Object { $_ })` at the call site.

### Graph goes through `Invoke-IslGraphRequest`, and the endpoints are the ones that still exist

Every Graph call goes through the private `Invoke-IslGraphRequest` seam so the suites can mock it
and never touch a tenant. `mobileApps/{id}/installSummary`, `deviceStatuses` and `userStatuses`
are gone and `reports/getAppsInstallSummaryReport` returns 400; app install counts come from the
`AppInstallStatusAggregate` export job through `Get-IslExportReport`. `$select=installExperience`
on `mobileApps/{id}` is refused (derived-type property) - fetch the app without `$select`.

### Pester scoping rules the suites depend on

A `Mock` defined in `BeforeEach` is not active in a Context's `BeforeAll`; define mocks in the
Describe's `BeforeAll`. `Should-Invoke` for a call made in `BeforeAll` needs `-Scope Context`.
`Tests/Invoke-Tests.ps1` shuffles every run, locally and in each CI job, and puts the seed in its
failure message; a test that only passes in declaration order fails there first, and
`-ShuffleSeed` runs that order again.

### The MAML filename carries a capital H

`en-US/IntuneScriptLab-Help.xml`, matching every `.EXTERNALHELP IntuneScriptLab-Help.xml` keyword
in `Public/`. `Export-MamlCommandHelp` produces that name while most documentation writes
`-help.xml`. On Windows the mismatch is invisible; on a case-sensitive filesystem `Get-Help`
silently falls back to a reflected stub and every command loses its help. The `help` job in
`quality-gates.yml` runs on Linux for this reason.

### Help is compiled, and stale help beats correct help

`docs/IntuneScriptLab/*.md` is the source; `en-US/IntuneScriptLab-Help.xml` is the artifact. After
editing anything under `docs/`, run `./Build/Build-Help.ps1` and commit the rebuilt MAML in the
same change. CI compares a fresh build against the committed file byte for byte, with PlatyPS
pinned to 1.0.3 so that comparison is stable.

For a new command, write full comment-based help first, run `Build-Help.ps1` (it seeds the
Markdown from `Get-Help`), then trim the block to `.EXTERNALHELP IntuneScriptLab-Help.xml` plus a
one-line `.SYNOPSIS`, delete the ALIASES placeholder and fill INPUTS and OUTPUTS by hand. Adding
`.EXTERNALHELP` before the first generation leaves the Markdown full of `{{ Fill in }}`.

### Never `Publish-PSResource -Path .`

This repository *is* the module root, so packaging it directly ships the whole working tree,
including `.git`, the tests and the validation kit with its tenant-derived findings. Gallery
versions can never be deleted, only unlisted, and the `.nupkg` stays downloadable afterwards.

Always publish through `Build/Publish-Module.ps1`, which stages an **allowlist** into a
git-ignored `out/`. A new folder does not ship until it is named in `$shipFiles` or
`$shipFolders`. It then imports the staged copy in a fresh process, analyzes a sample detection
script, checks the PSScriptAnalyzer rules module is present and that every command and the about
topic serve their help, before anything is uploaded. `Examples/` and `PSScriptAnalyzer/` ship;
`Validation/`, `Tests/`, `docs/` and `Build/` do not.

### A command that runs a script or writes a report asks `ShouldProcess`; nothing else does

`-WhatIf` sets `$WhatIfPreference` for everything a command calls, and a caller's own preference
reaches the module the same way. The cmdlets inside the harness used to obey it: `Copy-Item`
skipped the copy of the script, the host was started on a file that was not there, and its
complaint came back as the script's result (#88). So the rule has two halves. The five
`Invoke-Intune*Test` commands, the two `Export-` commands and `Get-IntuneScriptHealth` declare
`SupportsShouldProcess` and ask once, before anything runs or is written, and return nothing when
the answer is no. Every internal operation - the run folder, the copy, a work folder, the removal
of a scheduled task - passes `-WhatIf:$false`, and a call from one gated command to another passes
`-Confirm:$false`, so that one run asks once. `Tests/Unit/Module.WhatIf.Tests.ps1` checks the
preview on the disk, with scripts that leave a marker file when they run.

Of the scheduled-task cmdlets only `Unregister-ScheduledTask` has `-WhatIf`. Under a preference
the task was registered and started, and then left behind.

### `$WhatIfPreference` is inherited by child scopes

Under `Publish-Module.ps1 -WhatIf`, the preference reaches the staging cmdlets and `Build-Help.ps1`.
Staging cmdlets are pinned `-WhatIf:$false` and the help build runs with the preference cleared,
or the rehearsal copies and compiles nothing and stops verifying what it exists to verify. Only
the publish itself is gated by `ShouldProcess`.

### Releases are tag-driven and the tag must match the manifest

Bump `ModuleVersion`, update `CHANGELOG.md` and the manifest's `ReleaseNotes`, then
`git tag v<ModuleVersion> && git push origin v<ModuleVersion>`. `.github/workflows/release.yml`
re-runs every gate, rejects a tag that disagrees with the manifest, stages, verifies and publishes,
then creates the tag's GitHub release from that version's `## [<version>]` CHANGELOG section. That
section must exist and must not be empty, or the job fails; a dry run checks it too. A release that
already exists for the tag is left as written.
The API key is the `PSGALLERY_API_KEY` repository secret, passed as an environment variable.
Locally the script resolves `-ApiKey`, then `$env:PSGALLERY_API_KEY`, then a SecretManagement
secret named `PSGallery-ApiKey` in the default vault, or in the vault `-VaultName` names. No other
vault is searched, and the secret stays a `SecureString` until the publish call.

## Checks

```powershell
./Tests/Invoke-Tests.ps1                           # every suite, shuffled; suites that need elevation, a lab account or PSScriptAnalyzer skip themselves
./Tests/Invoke-Tests.ps1 -CodeCoverage             # the same with the 80% coverage gate, as the tests job runs it
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error, Warning -ExcludeRule PSAvoidLongLines
./Build/Build-Help.ps1                             # rebuild MAML after editing docs/
./Build/Build-RuleReference.ps1                    # rebuild docs/Rules.md after changing a rule
./Build/Publish-Module.ps1 -WhatIf                 # full release rehearsal, publishes nothing
```

`Tests/Invoke-Tests.ps1` is the one way the suites are run: it fails when Pester's result is not
`Passed` or when no tests ran, which a check of `FailedCount` alone does not. Run the unit suites
under Windows PowerShell 5.1 as well before pushing:

```powershell
powershell -NoProfile -File ./Tests/Invoke-Tests.ps1 -TestType Unit
```

The script sets strict mode for itself and turns it off around the Pester run, because the suites
and the validation kit are not written for strict mode yet. Remove that when they are. The module
does not depend on it: it sets its own strict mode in the root module.
