# IntuneScriptLab validation kit

Runs small probe scripts through Intune as remediations, platform scripts and Win32 app
detection rules, then compares what the device recorded with what Intune reports. The
output is [Findings.md](./Findings.md): each rule the IntuneScriptLab tool will encode,
with the documented behaviour next to the observed one.

## Files

| File | Purpose |
|---|---|
| `Probe.ps1` | Header prepended to every experiment. Records user, bitness, PowerShell version, command line, encoding and paths to `C:\ProgramData\IntuneScriptLab\<experiment>.jsonl` on the device. Windows PowerShell 5.1 only. |
| `Experiments.psd1` | The experiments: `Remediations`, `PlatformScripts` and `Win32Apps`. Each has a `Question`, a script body and optional `RunAs32Bit`, `RunAsAccount`, `Bom`, `Requirement`. Win32 entries can also carry `DetectionRules` / `RequirementRules` (file, registry, product code and script rule specs), `Intent` (`required` or `uninstall`), `EnforceSignatureCheck`, `Requirements` (base requirement properties by Graph name), `Filter` (an assignment filter rule and mode), `InstallContext`, `DependsOn`, `Supersedes`, `Assign = $false` and `Package` (a real MSI); remediations a `Schedule` (`RunOnce`, `Daily` or hourly with an `Interval`) and `DetectOnly`. |
| `GraphRules.ps1` | Builds the Graph rule objects (`win32LobAppFileSystemRule`, `win32LobAppRegistryRule`, `win32LobAppProductCodeRule`, `win32LobAppPowerShellScriptRule`) and remediation run schedules from experiment entries. No Graph calls, so `Tests\Unit` covers it directly. |
| `GuestAgent.ps1` | Runs PowerShell inside a lab VM through the QEMU guest agent (`Invoke-GuestPowerShell`) and fetches a large text file from it in checked chunks (`Read-GuestPayload`). Dot-sourced by the driver and by `Invoke-LabGuestScript.ps1`; see the guest agent notes under "Timing notes" for why it works the way it does. |
| `Fixtures.ps1` | Device-side fixtures the file, registry and MSI rule experiments look at: files with a known version, size and modified date, a `Program Files (x86)`-only file, `HKLM\SOFTWARE\IntuneScriptLab` in both registry views, and an MSI product survey. Run by `Prepare`. |
| `Invoke-ValidationRound.ps1` | Driver: `Prepare`, `Deploy`, `Trigger`, `Collect`, `Remove`. `Deploy -Name` and `Collect -AppName` take wildcards to keep a round to its own experiments (each app's install status is one report export job of 20-30 seconds, and the service runs them one at a time). |
| `Win32Content.ps1` | Packages `Win32Install.ps1` with IntuneWinAppUtil.exe and uploads the content to each app. |
| `Win32Install.ps1` | The install/uninstall script inside the shared `.intunewin`; it only writes a probe record. |
| `New-IntuneLabVm.ps1` | Clones a Proxmox template into a test VM, fixes the OOBE account screens, snapshots it. |
| `Invoke-LabGuestScript.ps1` | Delivers a local script to a lab VM through the QEMU guest agent in numbered base64 parts and runs it there as SYSTEM with the arguments given (`-ArgumentList '-AutoLogon'`). The way to run `New-IslHarnessUser.ps1` or any collection script on a VM without opening a console. |
| `New-IslHarnessUser.ps1` | Run on a lab device (as SYSTEM through the guest agent, or elevated): creates the standard local account the harness's `-Credential` runs scripts as, stores its generated password as a DPAPI credential for the running identity (`ISL_TEST_CREDENTIAL` for the UserContext integration suite) and, with `-AutoLogon`, makes it the console user at the next boot through the LSA secret. The password is never printed. |
| `New-IslDriveFixture.ps1` | Run on a lab device through `Invoke-LabGuestScript.ps1`: attaches a small virtual disk as a local `D:` and maps `X:` to a share inside the signed-in user's own session, the state REM-DRIVES-SYS (round 10) reports on; `-Remove` undoes it. Safe to run twice. |
| `Invoke-FilterProbe.ps1` | Sends a matrix of assignment filter rules through `assignmentFilters/validateFilter` and `evaluateAssignmentFilter` (the portal's Preview devices) and records what the service accepted, refused and matched, written against one enrolled device's own values. Creates nothing; needs a Graph session. Results in `Results\filter-probe.json`. |
| `Invoke-AssignmentProbe.ps1` | Creates six remediations that differ only in their assignment (none, exclusion only, include plus exclusion of the same group, run-once in the past, a user group) so the agent logs show which are delivered. Round 9's evidence (Findings, "Assignment sanity"); the policies stay deployed like the other ISL-* objects. |
| `Get-IslEspEvidence.ps1` | Run on a lab device as SYSTEM after an Enrollment Status Page run (`Invoke-LabGuestScript.ps1 -RemoteName Get-IslEspEvidence.ps1`): one JSON document with every probe record, the `Write-EspState` records, the FirstSync and `EnrollmentStatusTracking` registry bookkeeping, the Autopilot diagnostics and the page-relevant agent log lines. Round 8's evidence. |
| `Findings.md` | Results, documented vs observed. |
| `Tests/` | Pester 6.2 unit tests for the kit: `GraphRules.ps1` as it is, and the driver's helpers lifted out through the AST with `ssh` and `Invoke-MgGraphRequest` mocked. Run them from the Validation folder with `Invoke-Pester -Path .\Tests`. |
| `Results/` (gitignored) | Raw JSON from every `Collect`: Graph run states, device registry, probe records, log excerpts. |
| `Tools/` (gitignored) | `IntuneWinAppUtil.exe` from [microsoft/Microsoft-Win32-Content-Prep-Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool). |

## Prerequisites

- PowerShell 7.6+ and `Microsoft.Graph.Authentication`.
- An app registration with certificate auth and these application permissions:
  `DeviceManagementScripts.ReadWrite.All`, `DeviceManagementConfiguration.ReadWrite.All`,
  `DeviceManagementApps.ReadWrite.All`, `DeviceManagementManagedDevices.Read.All`,
  `Group.ReadWrite.All`, `Device.Read.All`.
  `Scripts\Entra\Grant-ClaudeDevTenantPermissions.ps1` grants them.
- A Proxmox host reachable over key-based SSH, a sysprepped Windows 11 Enterprise/Pro template
  with the QEMU guest agent installed, and a licensed test user (Windows E3/E5 for remediations).
- `Tools\IntuneWinAppUtil.exe` (only for the Win32 experiments). `Deploy` downloads it from
  Microsoft's GitHub repository when it is missing and refuses to run it unless its Authenticode
  signature is valid and Microsoft's. The binary is gitignored.

Use a dev tenant. Everything is created with an `ISL-` prefix so `Remove` can find it, but the
remediations are assigned hourly and will keep running on whatever is in the group.

## Workflow

```powershell
$conn = @{ TenantId = '<tenant>'; ClientId = '<app>'; CertificateThumbprint = '<thumbprint>' }
cd Scripts\Intune\IntuneScriptLab\Validation

# 1. Test VM. Ends at the OOBE account screen with a clean-oobe snapshot.
.\New-IntuneLabVm.ps1 -TemplateId 123 -VmId 125 -Name INTUNE-TEST-02

# 2. Join (manual): in the console choose "Set up for work or school" and sign in.
#    Signing in from Settings > Access work or school > Connect only *registers* the device;
#    use "Join this device to Microsoft Entra ID" there if you join after setup.
#    Then snapshot with memory so the enrolled, signed-in state can be restored:
ssh pve 'qm snapshot 125 joined --vmstate 1'

# 3. Device-side folder for the probes plus the rule fixtures from Fixtures.ps1 (once per device)
.\Invoke-ValidationRound.ps1 -Action Prepare -VmId 125

# 4. Policies, apps, group membership. Re-running skips what already exists,
#    so it doubles as "add another device to the group".
.\Invoke-ValidationRound.ps1 -Action Deploy @conn -AzureADDeviceId <entra deviceId from dsregcmd /status>

# 5. Optional: restart the agent so it fetches policy now (see timing notes below)
.\Invoke-ValidationRound.ps1 -Action Trigger -VmId 125

# 6. Collect Graph run states + device registry + probe records + log excerpts
.\Invoke-ValidationRound.ps1 -Action Collect @conn -VmId 125 -ResultsPath .\Results\joined

# 7. Tear down everything ISL-* in the tenant
.\Invoke-ValidationRound.ps1 -Action Remove @conn
```

Every action supports `-WhatIf`.

## Timing notes (from the runs, see Findings.md)

- Assignments reach a device 2–8 minutes after group membership changes. Win32 apps are also
  pushed by notification and can run within seconds of assignment.
- After the agent fetches remediation policy it queues the run **5 minutes later**. Restarting
  the agent before then discards the queued run, and a restart adds ~3 minutes of start-up delay.
  Restart once, then wait.
- Remediations run one at a time, ~15 s per policy.
- Re-assigning a Win32 app (`/assign` with an empty list, then with the group) triggers a push
  and gets it processed within ~2 minutes.
- Graph run states for remediations lagged the device by up to an hour; platform scripts and
  Win32 status appeared within seconds to minutes.
- Without a restart the agent fetches script and remediation policy every 8 hours; Win32 apps
  arrive by push within minutes. Leave one device untouched when the cadence itself is the question.
- Autopilot user-driven with an ESP (round 8, VM 126): enrollment to the agent service start 1 minute,
  first page check 1 minute later; the device setup phase ran the device platform script and then
  the two blocking apps one at a time (~50 s each, 135 s in all); the account setup phase took
  3 minutes; a required app outside the blocking list started 20 s after the page closed; the first
  remediation run came 3 minutes after that.
- The OOBE web sign-in expires after ~10 minutes idle ("Sorry, your sign-in timed out"); a user with
  no MFA method cannot get past "Keep your account secure" while the tenant requires MFA to register
  or join devices, and the Windows Hello PIN page after the account phase has no skip either.
- The guest agent as a transport, measured on VM 125 on 2026-10-05 after `Collect` failed with a
  JSON error in the middle of the device payload (the payload file on the device was intact; chunk
  154 of 179 had arrived with the right length and another chunk's text):
  - A result nobody collects stays with the agent, and a status call for a process id returns the
    **oldest** result held under it. Windows reuses process ids quickly: of 245 commands started
    without collecting their results, 29 ids were used two or three times, and asking for one of
    them returned the first command's output, then the second's, then the third's.
  - A status call that times out on the host (`qmp command 'guest-exec-status' failed - got
    timeout`) has still been answered by the agent. If the command had finished, the next call
    says `PID does not exist`: the result went with the reply nobody read.
  - So `GuestAgent.ps1` starts each command without waiting, asks for its result by id, has every
    command print a marker of its own first and passes over a result without it, and runs the
    command again when the agent holds nothing after a timed-out call. A snippet sent this way has
    to be safe to run twice. `Collect` also compares the SHA-256 of the assembled payload with the
    one the device computed.
  - A second copy of the detached runner finds the output file held by the first, skips the script
    and writes the done marker at once, so the launch sits behind a started marker.
- `Collect` runs the device script detached and polls a done marker, so no single guest agent call
  has to stay open for minutes, and uploads are numbered part files so a chunk written twice
  replaces itself.

## Adding an experiment

Add an entry to `Experiments.psd1` with a unique `Name` (it becomes `ISL-<Name>` in Intune and
the probe file name on the device), then run `Deploy` again. Keep bodies 5.1-compatible unless
the experiment is about incompatibility. `Write-ProbeRecord <Name> <phase>` records the launch
context; everything after it is the behaviour under test.

A Win32 experiment with no detection script uses `DetectionRules` instead, and its result is read
from the install probe: a rule that evaluates true leaves the app Installed with no install record,
a false one makes the agent run the install command (one `install` record) and then report
`0x87D1041C`, not detected after installation. Requirement rules are read the same way with a
detection script that always exits 1. Rule specs are documented in `GraphRules.ps1`; the fixtures
they look at are created by `Fixtures.ps1`, so add both when a new rule needs new device state.
