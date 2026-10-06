# Intune script behaviour: documented vs observed

Each rule the IntuneScriptLab tool encodes, with what Microsoft Learn says and what a real
device did. Documentation was read on 2026-09-23; observations come from
`Invoke-ValidationRound.ps1` runs against a test device.

**Test devices:** Windows 11 Enterprise LTSC 24H2 (26100), Proxmox VMs from the same image, Intune
Management Extension (IME) installed automatically at enrollment. Device A is **Entra registered**
(MDM enrolled through a local account's work account); device B is **Entra joined**. All 35
experiments of rounds 1-3 ran on both, as did the 17 requirement-rule apps of round 4, the 40
apps plus one remediation of round 5 and the 17 apps, two remediations and one platform script of
round 6; every SYSTEM-context result was identical on the two devices. See "Join type".

Legend: ✅ confirmed · ❌ contradicted · ⚠️ undocumented, observed · ⏳ pending

The module's findings carry an `Evidence` string ending in experiment IDs such as `REM-EXIT-2`,
`REM-RETURN-EXIT` or `W32-DET-NOOUT`. Those are the experiment names in
[Experiments.psd1](Experiments.psd1) (`REM-*` remediations, `PS-*` platform scripts, `W32-*`
Win32 apps); each row below summarises one or more of them, and the experiment's script body is
the exact thing that ran on the device.

## Sources

| Key | Page |
|---|---|
| REM | [Use Remediations](https://learn.microsoft.com/en-us/intune/device-management/tools/deploy-remediations) |
| PS | [Use PowerShell scripts on Windows devices](https://learn.microsoft.com/en-us/intune/device-management/tools/run-powershell-scripts-windows) |
| IME | [Intune Management Extension](https://learn.microsoft.com/en-us/intune/device-management/tools/management-extension-windows) |
| W32 | [Add a Win32 app](https://learn.microsoft.com/en-us/intune/app-management/deployment/add-win32) |
| REMREF | [Remediation script samples](https://learn.microsoft.com/en-us/intune/device-management/tools/ref-remediation-scripts) |
| GRAPH-HS | [deviceHealthScript (beta)](https://learn.microsoft.com/en-us/graph/api/resources/intune-devices-devicehealthscript?view=graph-rest-beta) |
| GRAPH-PS | [deviceManagementScript (beta)](https://learn.microsoft.com/en-us/graph/api/resources/intune-shared-devicemanagementscript?view=graph-rest-beta) |
| ESP | [Set up the Enrollment Status Page](https://learn.microsoft.com/intune/device-enrollment/windows/setup-status-page) |
| ESP-TS | [Troubleshooting the Enrollment Status Page](https://learn.microsoft.com/troubleshoot/mem/intune/device-enrollment/understand-troubleshoot-esp) |

## Graph API defaults

| Rule | Documented | Observed | |
|---|---|---|---|
| Platform script bitness when `runAs32Bit` omitted | Portal: 32-bit is default (PS) | Graph stores `runAs32Bit=false` (64-bit) | ⚠️ |
| Platform script context when `runAsAccount` omitted | Portal: logged-on user is default (PS) | Graph stores `runAsAccount=system` | ⚠️ |
| Remediation bitness / context when omitted | Portal recommends 32-bit; default not stated (REM) | Graph stores `runAs32Bit=false`, `runAsAccount=system` | ⚠️ |

Consequence for the tool: a script created through Graph or IaC gets **64-bit SYSTEM**, one created
in the portal with default toggles gets **32-bit** (and, for platform scripts, **user**). The same
script can behave differently depending on how it was deployed.

## Join type

| Rule | Documented | Observed | |
|---|---|---|---|
| IME supports Entra registered (WPJ) | Yes (IME) | IME installed and running on a registered device | ✅ |
| Remediations on Entra registered | Only joined / hybrid joined listed (REM) | **SYSTEM-context remediations run** (17/17 via a device group). The 2 **user-context** remediations were never delivered (IME resolved 17 of 19) | ❌ docs too strict / ⚠️ |
| Platform scripts on Entra registered | "don't receive the scripts" — but WPJ can be targeted with device groups (PS) | **SYSTEM-context scripts run** (5/5). The 1 user-context script was filtered out ("After filter, get 5 policies") | ❌ docs too strict / ⚠️ |
| User context on Entra registered | Not documented | **Deliberately skipped by the agent**: `[PowerShell] This is not AADJ/HAADJ device, skip user context for <policyId>` (IntuneManagementExtension.log). The policy is downloaded (`DownloadCount=1`) but never run. The user-context remediations were likewise not resolved (17 of 19). An active AAD user session makes no difference. Exception: Win32 *requirement* scripts in user context do run | ✅ |
| User context on Entra joined | Runs as the signed-in user (PS, REM) | All user-context experiments ran as `AzureAD\<user>` in the console session (session 2, `UserInteractive=True`), with the user's profile, `TEMP` and `APPDATA`; 64-bit and `runAs32Bit` both honoured; same `AgentExecutor.exe` → `powershell.exe -NoProfile -executionPolicy bypass -file` launch; registry `RunAsAccount=2` | ✅ |
| Policy delivery to a fresh joined device | Not documented | Device added to the group at 15:55; platform scripts and Win32 apps ran at 15:56–15:57 **without any agent restart** (the fresh enrollment's own check-in cadence); remediations followed the usual fetch + 5-minute queue | ⚠️ |
| Working directory of user-context scripts | Not documented | Usually `C:\WINDOWS\system32`, but one user-context platform script inherited `C:\WINDOWS\IMECache\<appId>_1` from a Win32 install the agent had just run. Scripts must not rely on the working directory | ⚠️ |

**Bottom line on join type:** SYSTEM-context remediations, platform scripts and Win32 apps (detection,
requirement, install) all work on an Entra *registered* device, with results identical to a joined one.
User-context remediations and platform scripts require Entra joined or hybrid joined (the agent skips them
otherwise); user-context Win32 requirement scripts run on both. The Remediations page's "joined or hybrid
joined" prerequisite is only true for user context; the platform-scripts page's "registered devices don't
receive the scripts" is wrong for SYSTEM context when targeted by device group.

IME log evidence (registered device): `IsDeviceWPJ()` throws from `NetGetAadJoinInformation`
(hr 1) because the device has no Entra *join* info, yet HealthScripts.log still reports
`Device WPJ? = True` and proceeds to request policies for the signed-in AAD user.

## Remediations

| Rule | Documented | Observed | |
|---|---|---|---|
| Remediation runs only on detection exit 1 | Yes: "any other exit code, the remediation script won't run" (REM) | **Any non-zero exit runs remediation.** Exit `2` and `-1` both ran it | ❌ |
| Unhandled `throw` in detection | Not documented | Process exits 1, so remediation runs. Status ends up Recurred because post-detection throws again | ⚠️ |
| Parse error (e.g. PS7 ternary under 5.1) | Not documented | Exit 1, so remediation runs; parser error lands in the error field | ⚠️ |
| Non-terminating error, no `exit` | Not documented | Exit 0 → "without issues"; the error text is still captured in the error field. Stderr does **not** affect remediation status (unlike Win32 detection) | ⚠️ |
| No `exit` statement | Not documented | Exit 0 → "without issues" | ⚠️ |
| `return` before `exit 1` (Microsoft sample pattern) | Samples use it (REMREF) | `return 1` ends the script with **exit 0**; `exit 1` is never reached, so remediation never runs. Captured output is `1` (the returned value) | ❌ sample bug |
| Output limit | 2,048 characters (REM) | Exactly 2,048, but Intune keeps the **last** 2,048 characters, not the first. The same applies to the error field | ✅ / ⚠️ |
| Which output line is reported | Not documented | **The last line of the console output** (`out-1`, `out-2`, `out-8` → `out-8`), and that console output **includes the host streams**: a trailing `Write-Host` was reported as `host-last`, `Write-Warning` as `WARNING: warn-last`, `Write-Verbose -Verbose` as `VERBOSE: verbose-last` (REM-OUT-HOSTLAST/WARNLAST/VERBLAST, round 3). An earlier version of this table said those streams were dropped; REM-OUT-STREAMS could not tell, because its last line was a Write-Output | ⚠️ |
| Error field | Not documented | Captures `Write-Error` records and raw `[Console]::Error` writes, multi-line, formatted as PowerShell error records | ⚠️ |
| PowerShell version | Not documented | Windows PowerShell 5.1 | ⚠️ |
| Launch command | Not documented | `AgentExecutor.exe -remediationScript <detect.ps1> <.output> <.error> <.timeout> 3600 <PSHOME> 0 <.exit> True` → `powershell.exe -NoProfile -executionPolicy bypass -file <detect.ps1>`. No `-NonInteractive` | ⚠️ |
| Timeout | Not documented | `3600` seconds (1 hour) passed to AgentExecutor, twice the platform-script timeout | ⚠️ |
| 32-bit host path | Not documented | `runAs32Bit=true` → `SysWOW64\WindowsPowerShell\v1.0\powershell.exe`, `Is64BitProcess=False` | ✅ |
| Script file on disk | Not documented | `C:\WINDOWS\IMECache\HealthScripts\<policyId>_<version>\detect.ps1` / `remediate.ps1`, bytes identical to upload | ⚠️ |
| Script decoding | UTF-8; no BOM when signature check is on (REM) | With BOM: literal `Grüße — ✓` correct. **Without BOM: decoded as ANSI** → `GrÃ¼ÃŸe â€" âœ“` | ❌ trap |
| Non-ASCII in captured output | Not documented | Output goes through the OEM console code page (437): even with a BOM, `Grüße — ✓` is reported as `Grüße - √` (best-fit, lossy) | ⚠️ |
| Execution order | Not documented | Sequential, ~15 s per detection/remediation pair; 17 policies took ~6 minutes | ⚠️ |
| Status mapping (device registry `RemediationStatus`) | Portal: Without issues / Fixed / Recurred / Failed | `4` = without issues (detect exit 0) · `1` = fixed (remediate, then detect exit 0) · `2` = recurred (post-detect still non-zero, including when remediation exited 0) · `3` = remediation failed (remediation exit non-zero; post-detect skipped) | ⚠️ |
| Status mapping (Graph `deviceRunStates`) | `detectionState` / `remediationState` enums (GRAPH-HS) | detect exit 0 → `detectionState=success`, `remediationState=skipped` · fixed → `fail` / `success` · post-detect still failing (exit 2, -1, throw, parse error, or remediation exited 0 but didn't fix) → `fail` / **`remediationFailed`** · remediation script exit non-zero → `fail` / **`scriptError`**. So `remediationFailed` means "recurred", not "the remediation script failed" | ⚠️ |
| Reporting latency to Graph | Recurring scripts report on change only (REM) | `lastStateUpdateDateTime` = 14:19:17, i.e. ~40 s after the last of the 17 policies finished (reported as one batch). The run states were still empty when queried at 14:23 and populated by 15:23 | ⚠️ |
| Result cache | Not documented | `HKLM\SOFTWARE\Microsoft\IntuneManagementExtension\SideCarPolicies\Scripts\Reports\<userId>\<policyId>_<version>\Result` (JSON with pre/post output, error and exit codes). Platform scripts: `...\IntuneManagementExtension\Policies\<userId>\<policyId>` (`Result`, `ErrorCode`, `DownloadCount`) | ⚠️ |
| First run after new assignment | Not documented; policy retrieval on IME start / sign-in / 8h (REM) | Policies received ~8 min after assignment (13:50). After each fetch the HS scheduler queues a run **5 minutes later** (`Job is queued and will be scheduled to run at ...`). Restarting IME before then discards the queued run | ⚠️ |

## Platform scripts

| Rule | Documented | Observed | |
|---|---|---|---|
| PowerShell version | Not documented | Windows PowerShell 5.1 (5.1.26100), Desktop edition | ⚠️ |
| Launch command | Troubleshooting snippet only (PS) | `AgentExecutor.exe -powershell <script> <.output> <.error> <.timeout> 1800 <PSHOME> 0 <0\|1>` → `powershell.exe -NoProfile -executionPolicy bypass -file <script>` | ✅ |
| `-NonInteractive` | Not documented | **Not passed**: `Read-Host`/`Pause` block until timeout instead of failing | ⚠️ |
| Timeout | 30 minutes (PS) | `1800` seconds passed to AgentExecutor | ✅ |
| `runAs32Bit=true` host | 32-bit host (PS) | `C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe`, `Is64BitProcess=False` | ✅ |
| `runAs32Bit=false` host | 64-bit host (PS) | `C:\Windows\System32\...`, last AgentExecutor arg `1` | ✅ |
| SYSTEM environment | Not documented | Session 0, `UserInteractive=False`, cwd `C:\WINDOWS\system32`, `TEMP=C:\WINDOWS\TEMP`, profile `systemprofile` | ⚠️ |
| Script file on disk | Not documented | `C:\Program Files (x86)\Microsoft Intune Management Extension\Policies\Scripts\<userId>_<policyId>.ps1`, bytes identical to upload (no BOM added or stripped) | ⚠️ |
| Encoding | "less than 200 KB (ASCII)" (PS) | UTF-8 without BOM is decoded as ANSI: `Grüße — ✓` became `GrÃ¼ÃŸe â€" âœ“` | ❌ trap |
| Time to first run after assignment | Not documented | Assigned 13:42; policy received 13:55:58 after IME restarts; ran 13:56 | ⚠️ |
| Retries on failure | 3 retries on next 3 IME check-ins (PS) | **Three runs in total per policy instance, then never again**, and only at a policy fetch: see "Remediation schedules and platform-script retries" (PS-FAIL) | ❌ |
| What `resultMessage` contains | "Details of execution output" (GRAPH-PS) | **All output lines, including `Write-Host`**, not truncated: a 6,000-character line came back whole (6,022 chars total). On failure it holds the error-record text (`Write-Error` formatted with script path); `errorCode=99`, `errorDescription` empty. Opposite of remediations (last line only, 2,048 cap) | ⚠️ |
| Reporting latency to Graph | Not documented | `lastStateUpdateDateTime` 13:56:41, i.e. within ~10 s of the scripts finishing | ⚠️ |

## Windows on ARM (local host survey, not Intune)

Not from an Intune run: a read-only survey of the in-box PowerShell hosts on a Windows 11 ARM64
device (Snapdragon X, build 26200), to know what "32-bit" and "64-bit" mean there. The Intune
agent's own behaviour on ARM64 is still ⏳.

| Fact | `System32` host | `SysWOW64` host |
|---|---|---|
| Binary | native **ARM64** | x86 (emulated) |
| `Is64BitProcess` / `ProcessArchitecture` | True / Arm64 | False / X86 |
| `PROCESSOR_ARCHITECTURE` / `PROCESSOR_ARCHITEW6432` | `ARM64` / — | `x86` / `ARM64` |
| `$env:ProgramFiles` / `ProgramW6432` | `C:\Program Files` / same | `C:\Program Files (x86)` / `C:\Program Files` |
| `${env:ProgramFiles(Arm)}` | `C:\Program Files (Arm)` | same |
| `HKLM:\SOFTWARE` | full view (19 subkeys) | WOW6432Node view (10 subkeys) |
| `Sysnative` | absent | present |
| `SysArm32`, x64 PowerShell | absent | absent |

Consequences: everything the 32-bit rules say applies unchanged to the x86 host on ARM64; the
"64-bit" host is native ARM64, so `PROCESSOR_ARCHITECTURE -eq 'AMD64'` is false there; there is
no x64 PowerShell to run at all.

## Win32 requirement scripts

Round 4: seventeen Win32 apps (`W32-REQ-*`) sharing the same package, each with a PowerShell
requirement rule and a detection script that always exits 1, so the install probe fires only when
the rule is met. Rules were created through Graph (`win32LobAppPowerShellScriptRule` with
`operationType`, `operator`, `comparisonValue`) and observed on the Entra-joined device; the
agent's AppWorkload.log shows only `result of requirementMet: True/False` and the applicability
state, never the compared values, so the semantics below come from which apps installed.

| Rule | Documented | Observed | |
|---|---|---|---|
| Evaluation order | Not documented | Detection first; the requirement runs only after "not detected", then detection again, then install (`ProcessRequirementRules` at 02:13:56 after the 02:13:56 detection) | ⚠️ |
| Launch | "if the exit code is 0, we'll detect the standard output" (W32) | `SideCarScriptRequirementManager` runs the script "in machine session" as SYSTEM, 64-bit, from `...\Content\DetectionScripts\<appId>_<n>.ps1`, 60-minute timeout; `runAs32Bit` gives `Is64BitProcess=False` (W32-REQ-BASE, W32-REQ-32) | ⚠️ |
| Exit code | Only exit 0 is evaluated (W32) | `ok` with `exit 1` → not applicable (W32-REQ-EXIT1) | ✅ |
| Stderr | Not documented | `ok` + `Write-Error` + exit 0 → **not applicable** (W32-REQ-STDERR) | ⚠️ |
| What is compared | "STDOUT" (W32) | The **whole** stdout minus its final line break: `first`/`ok` and `ok`/`second` both failed `string equal ok` (W32-REQ-LASTLINE, W32-REQ-FIRSTLINE); `ok   ` (trailing spaces) failed too (W32-REQ-TRAIL) | ⚠️ |
| `Write-Host` | Not documented | **Counts**, as for detection: `Write-Host "ok"` → `requirementMet: True`, `Applicability 0` (W32-REQ-HOST). `Write-Host` ends its line with a bare LF (`6F 6B 0A`) where `Write-Output` uses CRLF; either is stripped. (That app's install then failed on a content download, `0x87D30065`, which is why no install probe fired) | ⚠️ |
| Launch and cwd | Not documented | Identical to detection: `AgentExecutor.exe -powershellDetection <script> <result> <error> <timeout> 3600 <PSHOME> 0 <exitcode> False` → `powershell.exe -NoProfile -executionPolicy bypass -file`; working directory was `C:\Program Files (x86)\Microsoft Intune Management Extension` for the whole applicability pass | ⚠️ |
| No output | Not documented | Not applicable (W32-REQ-NOOUT) | ⚠️ |
| String comparison | Not documented | **Case-insensitive**: `OK` met `equal ok` (W32-REQ-CASE); `notEqual bad` met by `ok` (W32-REQ-NOTEQ) | ⚠️ |
| Integer | Data type selectable (W32) | `5 greaterThan 3` met; `five` → not applicable (W32-REQ-INT, W32-REQ-INTBAD) | ✅ |
| Float | Data type selectable (W32) | `1.5 greaterThan 1.25` met (W32-REQ-FLOAT) | ✅ |
| Version | Data type selectable (W32) | `2.10.0 greaterThanOrEqual 2.9.0` met, which a string compare would deny (W32-REQ-VER) | ✅ |
| Boolean | Data type selectable (W32) | `$true` (prints `True`) `equal true` met (W32-REQ-BOOL) | ✅ |
| DateTime | Data type selectable (W32) | `2026-01-15 greaterThan 2026-01-01T00:00:00Z` met (W32-REQ-DATE) | ✅ |
| Not-applicable reporting | Not documented | Portal / `DeviceInstallStatusByApp` report: **Not applicable**, details "PowerShell script requirement rule is not met." Device: `ComplianceStateMessage` `Applicability 1008`, `ComplianceState 2`, `DesiredState 0`. An output that does not parse as the rule's type (`five` for an integer rule) is reported differently: `Applicability 1` and **no** details text (W32-REQ-INTBAD) | ⚠️ |
| After a met rule | Not documented | Install ran and, because these detections always exit 1, every met app ended **Failed** `0x87D1041C` "not detected after installation complete" with `Applicability 0`, `DesiredState 2` | ✅ |

**For the tool:** `Invoke-IntuneRequirementTest` and the `Win32Requirement` branch of `IslOutputIssue`
encode this: exactly one line of output equal to the value (`Write-Output` or `Write-Host`, nothing
else), exit 0, nothing on stderr, typed comparisons with a case-insensitive string.

## Win32 file, registry and MSI rules

Round 5: forty Win32 apps sharing the round-4 package (`W32-FILE-*`, `W32-REG-*`, `W32-MSI-*`,
`W32-MULTI-*`, `W32-RREQ-*`, `W32-DET-SIGCHECK`, `W32-UNINSTALL`) plus one remediation
(`REM-RUNONCE`), created through Graph with `win32LobAppFileSystemRule`, `win32LobAppRegistryRule`,
`win32LobAppProductCodeRule` and `win32LobAppPowerShellScriptRule` objects, on both devices with
the same results. `Fixtures.ps1` put the files and registry keys in place. A detection rule's
verdict is read from the install probe: a rule the agent finds true leaves the app **Installed**
with no install record; one it finds false makes the install command run (an `install` record)
and the app end in `0x87D1041C`, not detected after installation. The rule engine logs only
`SideCarRegistryDetectionManager ... applicationDetectedByCurrentRule: True/False as system`; the
compared values never appear, so the semantics come from which apps installed.

| Rule | Documented | Observed | |
|---|---|---|---|
| File exists | File or folder exists (W32) | Present file → Installed; missing file → install ran, 0x87D1041C (W32-FILE-EXISTS, W32-FILE-MISSING) | ✅ |
| File doesNotExist | Listed for file rules in the beta Graph enums and accepted by the API | **Not evaluated by the agent as a detection rule**: on a missing file the app was not detected (install ran, W32-FILE-NOTEXIST); on a present file the detection ended `Failed / NotComputed` and the portal shows **Invalid detection rule or unable to parse detection rule** `0x87D30004` (W32-FILE-NOTEXIST-FALSE). The registry doesNotExist rule works (below) | ❌ |
| File version | Version semantics (Graph docs) | File version 10.0.26100.x: `greaterThanOrEqual 9.0` detected, `lessThan 9.0` not, so a version compare, not a string one (W32-FILE-VER-GE, W32-FILE-VER-LT) | ✅ |
| File sizeInMB | Size in MiB rounded down, integer compare (Graph docs) | 2 MiB file: `equal 2` detected, `greaterThan 2` not (W32-FILE-SIZE-EQ, W32-FILE-SIZE-GT) | ✅ |
| File modifiedDate | DateTime compare | File modified 2024-06-15: `greaterThan 2024-01-01T00:00:00Z` detected, `lessThan` not (W32-FILE-DATE-GT, W32-FILE-DATE-LT) | ✅ |
| `%ProgramFiles%` and check32BitOn64System | "expand environment variables in the 32-bit context" (Graph) | Off: `%ProgramFiles%` is `C:\Program Files` even though the agent is a 32-bit process, and a `Program Files (x86)`-only file is not detected; on: it is `C:\Program Files (x86)` and the file is detected (W32-FILE-PF-64, W32-FILE-PF-32) | ✅ |
| Registry key / value exists, key doesNotExist | Exists / does not exist (W32) | As documented, including doesNotExist on a missing key → detected (W32-REG-KEY-EXISTS, W32-REG-KEY-MISSING, W32-REG-KEY-NOTEXIST, W32-REG-VAL-EXISTS) | ✅ |
| Registry string | String comparison | **Case-insensitive**: `equal intunescriptlab` detected on the value `IntuneScriptLab` (W32-REG-STR-CASE); `equal other` not (W32-REG-STR-EQ, W32-REG-STR-NE) | ⚠️ |
| Registry integer | Integer comparison | DWORD 42: `greaterThan 40` detected, `greaterThan 50` not; **a REG_SZ holding `42` is parsed and detected too** (W32-REG-INT-GT, W32-REG-INT-GT-FALSE, W32-REG-INT-ONSZ) | ✅ / ⚠️ |
| Registry version | Version semantics, string fallback (Graph docs) | REG_SZ `10.0.1`: `greaterThanOrEqual 9.0` detected, `lessThan 9.0` not (W32-REG-VER-GE, W32-REG-VER-LT) | ✅ |
| Registry check32BitOn64System | "search the 32-bit registry" | Off reads the 64-bit view (`View=64` matched), on reads `WOW6432Node` (`View=32` matched, `64` did not) (W32-REG-VIEW-64, W32-REG-VIEW-32, W32-REG-VIEW-32ON64) | ✅ |
| MSI product code | Product code detection (W32) | A 64-bit product (QEMU guest agent) and a WOW6432Node one (the Intune Management Extension itself) both detected; an uninstalled code not (W32-MSI-EXISTS, W32-MSI-32BIT, W32-MSI-MISSING) | ✅ |
| MSI product version | Version compare | 110.0.2: `greaterThanOrEqual 99.0.0` detected (a string compare would deny it), `greaterThan 200.0.0` not (W32-MSI-VER-GE, W32-MSI-VER-GT-FALSE) | ✅ |
| Several detection rules | All rules must be met (portal) | File true + file false → not detected; file true + registry true → detected (W32-MULTI-ONEFALSE, W32-MULTI-BOTHTRUE) | ✅ |
| When rules are evaluated | Not documented | Three times per flow, like scripts: before applicability, again after the download, and after the install; each pass logs one `SideCarRegistryDetectionManager` block per rule | ⚠️ |
| File / registry requirement rules | Requirement rule types (W32) | Met → applicable, install ran; unmet → **Not applicable** with "File system requirement rule is not met." (device `Applicability 1006`) or "Registry requirement rule is not met." (`Applicability 1007`); script rules were 1008 (W32-RREQ-FILE-MET, W32-RREQ-FILE-UNMET, W32-RREQ-REG-MET, W32-RREQ-REG-UNMET) | ⚠️ |

**For the tool:** `Test-IntuneWin32Rule` encodes every row; `Invoke-IntuneWin32AppTest -DetectionRule`
runs several rules with the all-must-match rule. File doesNotExist is reported not met with the
reason above rather than emulated as a working rule.

## Enforced signature check

| Rule | Documented | Observed | |
|---|---|---|---|
| Unsigned detection script with enforceSignatureCheck | "Enforce script signature check" runs the script only when it is signed by a trusted publisher (W32) | **The script never ran**: no probe record, AgentExecutor exit 1, AppWorkload.log `Checked Powershell script exitCode: 1 EnforceSignatureCheck: 1 ... applicationDetected: False`; treated as not detected, so the install ran (the unsigned `install.ps1` is not checked) and the app ended `0x87D1041C` after a second refused detection (W32-DET-SIGCHECK) | ✅ |

**For the tool:** `-EnforceSignatureCheck` on `Invoke-IntuneDetectionTest` / `Invoke-IntuneWin32AppTest`
refuses an unsigned script the same way, and the `IslSignatureIssue` rule flags it statically.

## Uninstall intent

| Rule | Documented | Observed | |
|---|---|---|---|
| Uninstall assignment flow | Uninstall runs the uninstall command when the app is detected (W32) | Detection (installed) → content download → detection again → uninstall command from the content folder in the 32-bit `powershell.exe` → detection (marker present, exit 1) → portal **Not installed**; device `EnforcementState 1000`, `ErrorCode 0`, `DesiredState 1`. About 40 seconds end to end (W32-UNINSTALL) | ✅ |

**For the tool:** `Invoke-IntuneWin32AppTest -Intent Uninstall -UninstallCommand` runs the same
sequence and reports Uninstalled, Still detected after uninstall, or Not installed.

## Remediation schedules and platform-script retries

| Rule | Documented | Observed | |
|---|---|---|---|
| Run-once schedule | `deviceHealthScriptRunOnceSchedule` with date, time, useUtc (GRAPH-HS) | HealthScripts.log `inspect once schedule ... UTC = True, Time = 4:42:55 Date = 9/24/2026`; the pair ran at 04:43:04 UTC, 9 seconds after the scheduled time, once; nothing more in the following three hours, later inspections show `next Run Time =` empty (REM-RUNONCE) | ✅ |
| Platform script retries | "If the script fails, it retries 3 times on the next 3 IME check-ins" (PS) | **Three runs per policy instance**, at download count 0, 1 and 2; at the next fetch the agent logged `has download count = 3` and `After filter, get 0 policies` and never ran it again (PS-FAIL, both devices; PS-FAIL-2 on the joined device reached its third run at the natural fetch eight hours after the second). Read as "3 retries after the first run" the docs are wrong; the total is three | ❌ |
| When retries happen | "next IME check-ins" (PS) | Script policy is fetched at an agent start or restart and otherwise **every 8 hours**: the registered device, never restarted after 04:33, fetched at 12:38 and 20:38 and ran PS-FAIL-2 at each (12:38:36, 20:38:37). The hourly Win32 check-ins in between fetched no script policy and produced no run. Docs say 8 hours; confirmed for the cadence, and it is the retry cadence too | ✅ |
| Policy instance re-scoping | Not documented | On the Entra-joined device the failed script was first processed under the signed-in user's id (three runs) and, hours later, again under the device id `00000000-...` with a fresh download count (three more runs). Each instance is counted on its own | ⚠️ |

**For the tool:** `Invoke-IntunePlatformScriptTest` adds a warning to a Failed result with the
three-run limit.

## Win32 requirements, filters, install context and relationships

Round 6: seventeen apps (`W32-REQ-OS-24H2`, `W32-REQ-ARCH-ARM64`, `W32-REQ-DISK`, `W32-REQ-MEM`,
`W32-REQ-CPU`, `W32-FILTER-*`, `W32-USER-INSTALL`, `W32-DEP*`, `W32-SUP-*`, `W32-MSI-7ZIP`), two
remediations (`REM-DAILY`, `REM-DETECTONLY`) and a platform script (`PS-FAIL-2`). The joined device
was restarted to fetch policy; the registered device was left alone the whole day so the natural
cadence could be seen.

| Rule | Documented | Observed | |
|---|---|---|---|
| Base requirements: OS release | Minimum operating system (W32) | `minimumSupportedWindowsRelease = Windows11_24H2` on a 24H2 device: applicable, install ran (W32-REQ-OS-24H2) | ✅ |
| Base requirements: architecture | Check operating system architecture (W32) | `allowedArchitectures = arm64` on x64: **Not applicable**, "Device architecture (e.g. x86/amd64) is not applicable for the application.", device `Applicability 1000` (W32-REQ-ARCH-ARM64) | ✅ |
| Base requirements: disk, memory, processors | Minimum free disk space, memory, number of processors (W32) | Not applicable with "Available disk space on the target device is less than the configured minimum." (`Applicability 1001`), "Amount of RAM on the target device is less than the configured minimum." (`1003`), "Count of logical processors on the target device is less than the configured minimum." (`1004`) (W32-REQ-DISK, W32-REQ-MEM, W32-REQ-CPU). Together with rounds 4 and 5: file rule 1006, registry rule 1007, script rule 1008 | ⚠️ |
| Detection before applicability | Not documented | The detection script ran once for every not-applicable app, including the architecture one, before the applicability verdict; the same order as with requirement rules (round 4) | ⚠️ |
| Assignment filters | Include/exclude filters on device properties (Intune filters docs) | `(device.deviceName -eq "<joined>")` include: the joined device installed, the registered one reported **Not applicable / "Filters criteria are not met."**; exclude: the reverse (W32-FILTER-INCLUDE, W32-FILTER-EXCLUDE). AppWorkload.log: `All apps in the subgraph are not applicable due to assignment filters. Skipping processing.` The filtered-out app leaves no registry state on the device | ✅ |
| User install context, device-targeted | Install behavior User (W32) | **Never installed on either device**: "will not be evaluated as it has user install context and this is a userless check-in. The app will be reported as not applicable." Portal: Not applicable with no details, device `Applicability 1011`, `ComplianceState 5`. A user-context app assigned to a device group needs a user check-in, which the device-group assignment never produced on either join type (W32-USER-INSTALL) | ⚠️ |
| Dependency, autoInstall | Dependent apps are installed first (W32) | Parent detection → child detection, child download, child install (08:56:44) → parent detection, download, install (08:57:22). The unassigned child shows no Intune status ("displayed only if the app is targeted", as documented) but full device-side state (W32-DEP-PARENT, W32-DEP-CHILD) | ✅ |
| Dependency, detect | The child must be detected before the parent installs (Graph `dependencyType detect`) | Child detection, parent detection, then nothing: parent **Not installed / "1 or more dependent apps are configured to not automatically install."** on both devices; the parent's install never ran (W32-DEPD-PARENT) | ✅ |
| Supersedence, update | Update replaces the old version (W32) | New app detection, old app detection, new app installed; **the old app stays installed** (marker present, portal Installed). New app details: "Superseded applications are detected." (W32-SUP-NEW-A, W32-SUP-OLD-A) | ✅ |
| Supersedence, replace | Replace uninstalls the old app first (W32) | Old detection, new detection, old detection, **old uninstall command (09:07:14)**, new detection, old detection, **new install (09:07:47)**, both detections again. Old app: Not installed / "App was removed in order to install a superseding app.", device `DesiredState 1` (W32-SUP-OLD-B, W32-SUP-NEW-B) | ✅ |
| MSI package | MSI apps are Win32 apps with generated product-code detection (W32) | A 7-Zip MSI packaged with IntuneWinAppUtil: `msiInformation` from the package XML, `msiexec /i ... /qn` install, product code detection, Installed on both devices (W32-MSI-7ZIP) | ✅ |
| Win32 re-evaluation | Not documented for installed / not-applicable apps | Every app of the round was re-detected 8 hours after its first evaluation on the joined device (16:58-17:01 after 08:53-09:09) and 9 hours on the registered one (18:05 after 08:49-09:08), the not-applicable ones included | ⚠️ |

**For the tool:** `Test-IntuneWin32Requirement` evaluates the base requirements against the local
device with these codes and messages, and `Invoke-IntuneWin32AppTest -InstallContext User` warns
that a device-targeted assignment never installs a user-context app.

The relationship flows were replayed on VM 126 on 2026-09-28 (the six assigned apps of this round
added to ISL-ESP-Devices) to capture the agent's own lines for the event table:

| Line | Observed | |
|---|---|---|
| `[V3Processor] Processing subgraph with app ids: <a>, <b>` | An app with a dependency or a supersedence is processed together with its relative as one subgraph; a lone app is a subgraph of one. `Reevaluation interval is not expired for subgraph ... Skipping processing` and `All of the apps in the subgraph require user-context processing, and the target user is not logged in` are the two skips seen | ⚠️ |
| `Sending status ... "ReportingImpact":{"DesiredState":d,"Classification":c,"ConflictReason":r,"ImpactingApps":[{"AppId":"<relative>"` | The report of an app in a relationship names the relative. Seen: the parent of an autoInstall dependency and the superseding app with Classification 2, ConflictReason 0; the superseded app with DesiredState 2, Classification 3; the parent of a detect-only dependency whose child is absent with ResultantAppState 3, Classification 1, **ConflictReason 2**, the portal's "1 or more dependent apps are configured to not automatically install" | ⚠️ |
| `-toast "ToastDependencyAppInstall"` | The agent raised the dependency toast when it installed the child for the parent | ⚠️ |
| `Not sending status update ... because the app does not have available, required, or uninstall intent` | The unassigned child is evaluated and installed through the relationship but reports nothing on its own, the reason the portal shows no status for it | ⚠️ |
| `[DownloadActionHandler] Handler invoked for policy with id: <id> and version: n` | The content download step between applicability and the pre-install detection; the child downloaded and installed (17:44:36-17:45:08) before the parent's download (17:45:08), as in round 6 | ✅ |

## Remediation daily schedule and detect-only assignment

| Rule | Documented | Observed | |
|---|---|---|---|
| Daily schedule | `deviceHealthScriptDailySchedule` time, useUtc (GRAPH-HS) | HealthScripts.log `inspect daily schedule ... UTC = True, Time = 9:02:35 AM`; ran at 09:02:44 on the joined device, 9 seconds after the time. The registered device only fetched the policy at 12:38, after the scheduled time, and ran it once immediately (12:37:17); neither ran it again that day. The following days on the joined device: 09-25 at 09:07:59 (the agent had been restarted at 08:35 that morning and its poll was offset), 09-26 and 09-27 at 09:02:42, seven seconds after the time, one cycle a day (REM-DAILY, 12 records over four days); `Daily handler: last execution time for <id> is ...` is inspected every hour in between | ✅ |
| Hourly schedule, cadence | `deviceHealthScriptHourlySchedule` interval 1 (GRAPH-HS) | Not a fixed clock: cycles on the joined device came 60 to 66 minutes apart (09-25: 10:47, 11:47, 12:47, 13:47, 14:48, 15:48, 16:48, 17:51; 09-27: 12:30, 13:36, 14:42, 15:47, 16:53, 17:59, 19:05, 20:10, 21:16), the interval measured from the previous cycle and rounded up to the runner's poll, so "hourly" drifts by up to a few minutes per cycle (REM-DETECTONLY, 123 cycles) | ⚠️ |
| `runRemediationScript = false` through Graph | "Determine whether we want to run detection script only or run both" (GRAPH-HS) | **Not a switch.** With a remediation script uploaded, the remediation ran every hour on both devices regardless of the assignment value (REM-DETECTONLY, 16 cycles on the joined device: detection, remediation, detection each hour); Graph reads `runRemediationScript` back as `false` on every assignment and `PATCH` on it is rejected (400). The portal's "Run remediation script" is a read-out of whether a remediation script exists on the policy. The same policy recreated on 09-25 with `detectionScriptContent` only (no `remediationScriptContent`, hourly, the agent restarted on the joined device): policy fetched 08:40:13, first cycle 08:45:20 ran **the detection alone**, HealthScripts.log "pre-remdiation detection script compliance result ... is False" followed by the result upload with no remediation launch; the probe file shows a lone `detection` record where every earlier cycle had three, and Graph `deviceRunStates` reports `detectionState fail, remediationState skipped` | ⚠️ docs |

## What a script can rely on: modules, the gallery, the execution policy, the size limit

Round 7 (2026-09-28), five remediations and one platform script on the joined
device, the agent restarted once to fetch them.

| Rule | Documented | Observed | |
|---|---|---|---|
| Execution policy | Scripts run regardless of the device's execution policy (PS) | AgentExecutor launches every script as `powershell.exe -NoProfile -executionPolicy bypass -file <script>`; inside a remediation `Get-ExecutionPolicy -List` read `MachinePolicy=Undefined;UserPolicy=Undefined;Process=Bypass;CurrentUser=Undefined;LocalMachine=Undefined` (REM-EXECPOLICY). A `Set-ExecutionPolicy` in a script changes nothing for that run; any scope but Process changes the device's policy as SYSTEM | ✅ |
| Module path under SYSTEM | Not documented | `$env:PSModulePath` in a SYSTEM remediation is `WindowsPowerShell\Modules;C:\Program Files\WindowsPowerShell\Modules;C:\WINDOWS\system32\WindowsPowerShell\v1.0\Modules`: the first entry is a **relative** path, because SYSTEM has no Documents folder to resolve, so a module installed with `-Scope CurrentUser` as SYSTEM lands nowhere useful. 90 modules were available on a plain Windows 11 device, the same list as `Get-Module -ListAvailable` under SYSTEM outside the agent (REM-PSMODULEPATH; the list is Get-IslInboxModule) | ⚠️ |
| `Install-Module` from a remediation | Not documented | **Hangs the queue.** `Find-Module` and `Install-Module -Scope CurrentUser -Force` in a SYSTEM detection script never returned: no NuGet provider on the device, no network connection from the process, 12 s of CPU in 20 minutes, 14 threads, stuck on the provider-bootstrap prompt that a non-interactive session cannot answer. Because remediations run one at a time, every remediation queued behind it waited too; the agent killed it at exactly 60 minutes (AgentExecutor.log `Error:Powershell script execution timed out. timeout = 3600 seconds`, agent log `exitCode = 2147483647`), Graph reports `detectionState scriptError`, and the queue moved on; the two remediations behind it ran an hour late (REM-INSTALL-MODULE). It did the same every hourly cycle afterwards and held round 10's seven detections for 70 minutes, so its assignment was removed on 2026-10-06; the policy stays in the tenant, unassigned | ⚠️ |
| `#Requires -Modules` for a module the device lacks | The script does not run (PS docs on #Requires) | As documented, and what Intune makes of it: the detection exits 1 without running, stderr `The script 'detect.ps1' cannot be run because the following modules that are specified by the "#requires" statements of the script are missing: IslNoSuchModule` (`ScriptRequiresMissingModules`), so the remediation script **runs** (exit 0), the post-detection fails the same way, and Graph reports `detectionState fail, remediationState remediationFailed` with the error text in both detection outputs (REM-REQUIRES-MODULE) | ✅ |
| Script size | "Scripts must be less than 200 KB" (REM, PS) | Not enforced at 200 KB. Through the Graph API a remediation of 504 KB and a platform script of 660 KB were accepted; 512 KB and 680 KB were refused with a generic "An error has occurred" (no size in the message). On the device a 500 KB platform script ran (PS-SIZE-500KB, probe record at 00:31:49) and a 250 KB remediation ran and reported `big script ran` with `detectionState success` (REM-SIZE-250KB) | ❌ |

## Assignment filter rules: what the service accepts and how it matches

Probe (2026-09-28, `Invoke-FilterProbe.ps1`, nothing created): 114 rules through
`deviceManagement/assignmentFilters/validateFilter` for the Windows 10 and later platform (FLT-V,
FLT-W, FLT-X) and 84 through `deviceManagement/evaluateAssignmentFilter`, the call behind the
portal's Preview devices, against the two enrolled devices (FLT-E, FLT-F, FLT-Y). The evaluator
returned the joined device as deviceName `KRBETYP-AIEPVQ5`, cpuArchitecture `amd64`, deviceTrustType
`Azure AD joined`, manufacturer `QEMU`, model `Standard PC (Q35 + ICH9, 2009)`, operatingSystemSKU
`EnterpriseSEval` (Win32_OperatingSystem SKU 129; managedDevice.skuFamily says `Enterprise`),
osVersion `10.0.26100.9457`, deviceOwnership `Corporate`, enrollmentProfileName and deviceCategory
empty, isTpmAttested `False`; the registered device as `Azure AD registered` / `Personal`. Its
columns are deviceCategory, cpuArchitecture, deviceId, deviceName, enrollmentProfileName,
isTpmAttested, isRooted, deviceTrustType, manufacturer, model, operatingSystemSKU,
operatingSystemVersion (a number with 8-digit padded parts: 10.0.26100.9457 is 1.00000000000026E+25,
which is how the ordering works), osVersion, deviceOwnership, userPrincipalName.

### Syntax

| Rule | Documented | Observed | |
|---|---|---|---|
| Operators | eq, ne, startsWith, contains, notContains, in, notIn; gt, ge, lt, le on operatingSystemVersion | Exactly those. `-notStartsWith`, `-endsWith`, `-notEndsWith`, `not`, `-not`, `!`, `-equals`, `xor` refused (FLT-V02 to V07, V49, V50) | ✅ |
| Dash and casing | `-eq` or `eq`; "properties, operations, and values are case insensitive" | Both forms; `-EQ`, `AND`, `-AND`, `-IN`, `-NOTIN`, `OR`, `DEVICE.DEVICENAME` all accepted (FLT-V08 to V11, V15, W19, W29) | ✅ |
| Quoting | Double-quoted values in every example | Single quotes, an unquoted word and a bare number refused (FLT-V12, V13, V58). No escape exists: `\"` and `""` inside a string refused (V44, V45); an apostrophe, a backslash and a tab inside are fine (V43, W36, W37) | ⚠️ |
| Parentheses | "Parentheses and nested parentheses are supported" | Optional around a clause and around an and-chain (FLT-V14, W10, W11, W12, V34); unbalanced, empty `()`, a missing connector or a trailing connector refused (W07, W08, W09, V41, V42, W28, X07) | ✅ |
| Precedence | Not documented | `and` binds tighter than `or`: `true or false and false` matched, `nope or me and registered` did not (FLT-E27, E28, F09); parentheses override it (F08) | ⚠️ |
| Null | "Null or $Null as a value with the -Equals and -NotEquals operators" | `$null` and `null` with `-eq` / `-ne` on string and enumerated properties (FLT-V28, V29, V52, V63, W31, W32); refused with `-startsWith` / `-contains`, inside a list and on operatingSystemVersion (V31, W40, W15, W16, V64). `"null"` in quotes is the string (V30) | ✅ |
| Lists | `-in` / `-notIn` "for array value types" | A bare string after `-in` is accepted and works as a one-item list (FLT-V18, F02, W18); a trailing comma is tolerated (V46); an empty list is refused (V53). `-eq` and `-ne` with a list are refused by validateFilter, although the evaluator reads them as any-of (X01, X02, Y01, Y02, Y05) | ⚠️ |
| Empty strings | Not documented | `""` refused with every operator (FLT-V36, W03 to W05); `""` inside a list accepted (W06); `" "` accepted, and `-contains " "` matches every device (W27, Y03) | ⚠️ |
| Property and operator pairs | Per-property operator lists in the reference | As documented: `-gt` on a string, `-startsWith` on operatingSystemVersion, `-gt` on osVersion, `-contains` / `-startsWith` on cpuArchitecture and deviceTrustType, `-startsWith` / `-in` on deviceOwnership, `-in` on operatingSystemVersion all refused (FLT-V20, V23, V24, V26, V61, V62, V39, X03, V56) | ✅ |
| Versions | operatingSystemVersion "version value" | Bare or quoted, 2 to 4 numeric parts (FLT-V21, V22, W01, W02, W17); 1 part and 5 parts refused (V47, V48); a part of 100000000 accepted (W35) | ✅ |
| Properties on Windows | The reference's Windows list | isRooted and deviceManagementType refused on windows10AndLater (FLT-V37, V60); app.* refused (V33); an unknown name refused (V32); deviceId and userPrincipalName refused although the evaluator returns them (W25, W26); isTpmAttested accepted with `-eq` / `-ne` although undocumented (W24, X04) | ⚠️ |
| Enumerated values | Documented sets (amd64 / x86 / arm64 / unknown; Azure AD joined / registered / Hybrid / Unknown; Personal / Corporate / Unknown) | Any string validates: `"x64"` and `"Microsoft Entra joined"` are accepted (FLT-V25, V27) and match no device (E07, F01); `"Unknown"` validates everywhere (W21 to W23) | ⚠️ |
| Whitespace | Not documented | Newlines and runs of spaces are fine (FLT-V35, W33); no whitespace between the tokens is refused (W13); a comment is refused (W38); an empty rule is a 400 (V51) | ✅ |

### Matching

| Rule | Documented | Observed | |
|---|---|---|---|
| Case | "case insensitive" | `-eq`, `-in`, `-contains`, `-startsWith` all case-insensitive, on every property tried (FLT-E01, E02, E16, E17, E39, F05, F14) | ✅ |
| Whitespace in values | Not documented | Leading and trailing spaces in a value are ignored, for `-eq`, `-in` and `-startsWith`, on strings and on both version properties (FLT-E30, E31, F11, F28, F34, F35) | ⚠️ |
| contains and startsWith | String operators | Substring and prefix, not the PowerShell collection operators (FLT-E02, E03, E33, F10, F29) | ✅ |
| A property without a value | Not documented | With enrollmentProfileName and deviceCategory empty: `-eq $null` matches, `-ne $null` does not; `-ne "a"`, `-notIn ["a"]`, `-notContains "a"` match; `-contains "a"`, `-startsWith "a"` do not (FLT-E21, E22, E25, F17 to F22). `-eq ""` is refused, so a missing value is tested with `$null` | ⚠️ |
| operatingSystemVersion | Version comparison | Numeric, missing parts as 0: on 10.0.26100.9457, `-eq 10.0.26100` no, `-ge 10.0.26100` yes, `-gt 10.0.26100.0` yes, `-lt` and `-ne` the exact version no; quoted works (FLT-E11 to E13, E37, E38, E41, E42, F03, F27, F32) | ✅ |
| osVersion | String | Exact string with `-eq` and `-in`, partial with `-startsWith` and `-contains`; `-eq "10.0.26100"` does not match 10.0.26100.9457 (FLT-E14, E15, E36, E40, F04) | ✅ |
| cpuArchitecture | amd64, x86, arm64, unknown | The x64 VMs are `amd64`; `"x64"` matches nothing (FLT-E06, E07, F16) | ✅ |
| deviceTrustType | Azure AD joined, Azure AD registered, Hybrid Azure AD joined, Unknown | Joined device `Azure AD joined`, registered device `Azure AD registered`; `"AzureADJoined"` and `"Microsoft Entra joined"` match nothing (FLT-E08 to E10, E43, F01) | ✅ |
| operatingSystemSKU | The reference's SKU name table | SKU 129 evaluates as `EnterpriseSEval`, not the `Enterprise` that managedDevice.skuFamily reports; `-eq "Enterprise"` matches nothing there (FLT-E19, F13 to F15) | ✅ |
| deviceOwnership | Personal, Corporate | managedDeviceOwnerType `company` is `Corporate`, `personal` is `Personal`; `"company"` matches nothing (FLT-E23, E24, E44) | ✅ |
| manufacturer, model | Strings | `QEMU` and `Standard PC (Q35 + ICH9, 2009)`: punctuation, partial and case all as expected (FLT-E16 to E18, F05, F06, F33) | ✅ |
| isTpmAttested | Not documented | `"False"` on both VMs with `-eq`, `-ne "True"` matches both (FLT-F25, Y04) | ⚠️ |

**For the tool:** `ConvertFrom-IslFilterRule` refuses what validateFilter refused and warns about
what validates but cannot match; `Test-IntuneAssignmentFilter` evaluates with the matching above,
reading this device's values or a described device; `Test-IntuneDeployedScript` reads the filter
on every assignment and reports `IslFilterIssue`. The unit tests of both encode every row.

## The harness as another account, against the agent's user-context launch

2026-09-28, VM 125: the module's `-Credential` (0.18.0) run as SYSTEM through the guest agent for
the standard local account `isl-user`, which held the console session (created by
`New-IslHarnessUser.ps1 -AutoLogon`), against the agent's own user-context launch recorded in
round 1 (REM-PROBE-USER64, `AzureAD\JeffStuhr`).

| Property | Agent (REM-PROBE-USER64) | Harness, interactive task | Harness, stored-password task |
|---|---|---|---|
| Identity | the signed-in user | `KRBETYP-AIEPVQ5\isl-user` | the account, but the task never started |
| Session | 2 (the console session), `UserInteractive` True | 1 (the console session), `UserInteractive` True | task result `0x80070569`: a standard user is not granted "Log on as a batch job", which a "run whether user is logged on or not" task needs; the module waited for its timeout (0.18.1 reports the code and the hint at once) |
| Working directory | `C:\WINDOWS\system32` | `C:\Windows\System32` | |
| Profile | the user's `USERPROFILE`, `TEMP`, `APPDATA` | `C:\Users\isl-user`, its `AppData\Local\Temp`, its `AppData\Roaming` | |
| Host and command line | 64-bit `powershell.exe -NoProfile -executionPolicy bypass -file <copy>`, parent `AgentExecutor.exe` | the same command line on a copy under `ProgramData\IntuneScriptLab\Runs`, parent `cmd.exe` (the task's wrapper); `-Architecture x86` gives `SysWOW64`, `Is64BitProcess` False | |
| Integrity | not recorded | Medium, not an administrator | |
| Remediation flow | detect, remediate, detect | `Fixed`, the marker file owned by `isl-user`; `RunAs` on every result names the account and the logon type | |

**For the tool:** an account with a session is the right way to run user-context scripts as
someone else; the stored-password fallback needs the batch logon right, and the launcher now
says so instead of timing out.

Re-checked 2026-09-29 on the same device (isl-user still without the batch logon right, its
console session active): the stored-password task no longer comes back with `0x80070569`. It sits
`Ready` with `LastTaskResult` `0x00041303` ("has not run yet"), `LastRunTime` unset, and no error
anywhere, and the launcher waited out its timeout. 0.26.0 treats five seconds of that after
`Start-ScheduledTask` as the refusal and reports it with the same hint.

2026-10-05, the same device, a Microsoft Entra account at the console. The tenant user
`isl-verylongusername-test01@4nlnm3.onmicrosoft.com` (27 characters before the `@`), display name
"Isl Verylongdisplayname Testaccount", signed in at the "Other user" prompt:

| Question | Observed |
|---|---|
| What Windows calls the account | `AzureAD\IslVerylongdisplayna`: the **display name** without its spaces, cut at 20 characters. Not the sign-in name and not a part of it (round 1 had the same shape: signed in as `betar@...`, running as `AzureAD\JeffStuhr`). `USERNAME`, the owner of the session's `explorer.exe` and the profile folder (`C:\Users\IslVerylongdisplayna`) all carry it; `whoami /upn` gives the sign-in name |
| What `query user` prints | ` islverylongdisplayna  console             2  Active      none   10/5/2026 11:05 AM`: the same name in lower case. The user name column is 22 characters wide and this name was cut at 20, so two spaces remained and the parser's split held. No name longer than 20 characters was seen |
| Name to SID (`NTAccount.Translate`, as SYSTEM) | `AzureAD\<sign-in name>` and `AzureAD\IslVerylongdisplayna` resolve to the account's SID (`S-1-12-1-...`), and the SID translates back to `AzureAD\IslVerylongdisplayna`. The bare sign-in name, the bare Windows name, `AzureAD\<part before the @>` and `AzureAD\<whole display name>` do not resolve |
| Which name a scheduled task takes for an interactive principal | Only `AzureAD\IslVerylongdisplayna`. The sign-in name and the SID string were both refused at registration: "No mapping between account names and security IDs was done" |
| The module before the change, `-Credential` named three ways | Sign-in name: refused at once, `No mapping between account names and security IDs was done`. `AzureAD\<sign-in name>`: no session found, fell back to the stored-password task, "The user name or password is incorrect". `AzureAD\IslVerylongdisplayna`: ran in the session |
| The module after it | All three ran the script inside the account's session: `who=AzureAD\IslVerylongdisplayna session=2 interactive=True`, `RunAs` naming the credential as given with `(Interactive)`; no task and no run folder left behind |

**For the tool:** the launcher matched `query user` against the credential's user name taken
apart as text, which can only work when the Windows name happens to equal that text. That holds
for a local account and fails for an Entra account whatever its length: the Windows name comes
from the display name. `Resolve-IslAccount` now asks Windows for the account's SID (trying
`AzureAD\` in front of a sign-in name) and for the name behind that SID; the interactive task is
registered for that name and the run folder is granted by SID.

2026-10-06, the same device and user: the session list no longer comes from `query user`, which
Windows Home editions do not ship and which prints localized text, but from the owners of each
desktop's `explorer.exe` and `sihost.exe` through CIM, and the credential is matched by SID. As
SYSTEM the device listed one session, `AzureAD\IslVerylongdisplayna`,
`S-1-12-1-1497552185-1263987200-3276725654-805488699`, id 2, the SID the sign-in name resolves to;
`-Credential` with the sign-in name, `AzureAD\<sign-in name>` and the Windows name each ran the
script inside session 2 (`interactive=True`) and left no task or run folder behind. On a Windows
11 Home machine without `query.exe` the same list named its one console session.

The stored-password path for the same Entra account, signed out, `Register-ScheduledTask -User
<name> -Password <password>` with the account's real password: the sign-in name is refused at
registration ("No mapping between account names and security IDs was done"); `AzureAD\<sign-in
name>` and `AzureAD\IslVerylongdisplayna` register, and the task then sits Ready with
`0x00041303` ("has not run yet"), `LastRunTime` unset, as the local standard user's did. With the
account granted `SeBatchLogonRight` for the length of the test (`secedit`, the right taken away
again afterwards) the result was the same for both names. An Entra account on this device
therefore runs through the harness only while it holds a session; the launcher registers the task
for the Windows name and, for an Entra account, says so instead of pointing at the right.

### Reporting latency, re-measured (2026-09-29)

| Kind | Device (log line, converted to UTC) | Graph | Lag |
|---|---|---|---|
| Remediation, changed result (REM-FIX after its marker was removed, hourly) | post-detection passed 01:37:34 | `lastStateUpdateDateTime` 02:42:58, `detectionState` fail / `remediationState` success | 65 min: the result rode the agent's next hourly report batch (`data in request` at 02:43:02 device time, 20 policies in one request); Graph wrote the state within seconds of the upload |
| Remediation, unchanged result (three hourly policies over four cycles) | runs logged every hour | `lastStateUpdateDateTime` unchanged since the last change (days earlier), `lastSyncDateTime` current | never: the agent logs "app result is the same as cached one, no need to save" and reports nothing, so `lastStateUpdateDateTime` is the last change, not the last run |
| Platform script (two policies, Failed) | 16:56:38 and 16:56:44 | `lastStateUpdateDateTime` 16:56:46 | 2-8 s |
| Win32 app install state (`DeviceInstallStatusByApp` export, two apps) | report lines 00:25:53 and 00:26:02 | `LastModifiedDateTime` 00:26:32 for both | 30-39 s |

The report line's `Result` code, matched against Graph on both lab devices: `3` when the detection
found no issue (`success` / `skipped`), `4` when the issue was found and the remediation ran, both
for a fix (`fail` / `success`) and for a recurrence (`fail` / `remediationFailed` or `scriptError`),
`5` when the detection script itself failed (`scriptError` / `skipped`). It is not the registry
`RemediationStatus` code set above.

## The Enrollment Status Page

Round 8, 2026-09-28, VM 126 (a fresh clone with SMBIOS serial `ISL-ESP-01`): hardware hash imported
to Autopilot, profile `ISLAutopilot` (user-driven, Entra join, device name template `ISL%SERIAL%`),
ESP profile `ISL-ESP` (priority 1, progress shown, 90 minutes, blocking list = ESP-DEV-W32-BLOCK1,
ESP-DEV-W32-BLOCK2 and ESP-USR-W32-BLOCK, device use allowed on failure), both assigned to the device
group ISL-ESP-Devices; the ESP-USR-* policies assigned to ISL-ESP-Users, whose only member is the
test user `isl-esp` (password only, no MFA method). The console was driven through the Proxmox
monitor. Every script recorded the page's state at its run time (`Write-EspState` in Probe.ps1) and
`Get-IslEspEvidence.ps1` collected the probe records, the tracking registry and the logs afterwards.

Timeline (UTC; the sign-in was accepted at 07:02):

| Time | What the device did |
|---|---|
| 07:04 | Entra joined, MDM enrolled as isl-esp, sidecar tracking policy created (`ExpectedPolicies` at 07:06:06) |
| 07:05:00 | IntuneManagementExtension service started (`DevicePreparation\PolicyProviders\Sidecar: InstallDurationInSec=118`) |
| 07:06:00 | first page check: `The EspPhase: DeviceSetup`; `Userless session, skip UserToken for device check-in` |
| 07:06:05 | **ESP-DEV-PS-SYS** (device-assigned SYSTEM platform script) launched, before any app was registered |
| 07:06:13 | selected apps requested: `Found 2 apps which need to be installed for current phase of ESP` |
| 07:06:31 | BLOCK1 then BLOCK2 registered for tracking (`InstallationState=1`) |
| 07:06:46–07:07:31 | **BLOCK1**: detection, detection, install, detection, `InProgress to Completed` |
| 07:07:37–07:08:18 | **BLOCK2** the same, started only after BLOCK1 completed |
| 07:08:20 | `All apps completed for device`, phase `AccountSetup`; FirstSync `ApplicationsDuration=135` |
| 07:08 | the user's session created (Autopilot signs the user in; `quser` logon time 7:08) |
| 07:09:46 | **ESP-USR-PS-USER** launched as the user (session 2, `UserInteractive` True) |
| 07:10:32 | **ESP-DEV-PS-SYS launched a second time**, keyed to the user's id, still SYSTEM in session 0 |
| 07:10:40 | **ESP-DEV-PS-USER** launched as the user |
| 07:10:44 | user's selected apps: `Found 1 apps`; USR-W32-BLOCK registered for the user (`./User/...` tracking path) |
| 07:10:50–07:12:02 | **USR-W32-BLOCK**: detection, detection, install, detection, all by SYSTEM; BLOCK1 and BLOCK2 re-detected |
| 07:11:22 | `all apps completed for user`; `ESP completed. Triggering immediate app workload check-in` |
| 07:12:22 | `RunNontrackedAppsCheckinImmediatelyAfterEsp` True: **NOBLOCK** detected, installed at 07:12:39 |
| 07:13:03 | **USR-W32-USERCTX** detected and installed as the user |
| 07:15:13 | **ESP-USR-REM-USER** detection as the user; 07:15:28 **ESP-DEV-REM-SYS** detection as SYSTEM |

The console after the account phase: "Use Windows Hello with your account – Your organization
requires you to set up your work or school account with Windows Hello Face, Fingerprint, or PIN",
with only an OK button.

| Rule | Documented | Observed | |
|---|---|---|---|
| Platform scripts and the page | "During ESP, SideCar tracks only Win32 apps (no PowerShell scripts)" (ESP-TS) | A device-assigned SYSTEM script ran in the **device setup phase, before the blocking apps** (07:06:05; apps registered 07:06:31), untracked: the phase does not wait for it and it cannot rely on anything the blocking apps install | ✅ / ⚠️ |
| User-context platform scripts | Not documented for the page | Both the device-assigned and the user-assigned user-context scripts ran at the **start of the account setup phase**, as the user in the console session, before the user's blocking app was registered | ⚠️ |
| Device script at the first sign-in | Not documented | The device-assigned SYSTEM script ran **again** 4 minutes after its device-phase run, as `<userId>_<policyId>.ps1` in the user's script batch, still SYSTEM in session 0: a device script is part of every user's first script check-in | ⚠️ |
| Blocking apps: order and concurrency | Not documented (ESP) | **One at a time, in policy-list order** (BLOCK1, created first, then BLOCK2); each app detection → detection → install → detection, ~50 s apiece; the two phases' selected lists are fetched separately (`Found 2 apps` / `Found 1 apps`) | ⚠️ |
| Required device app outside the blocking list | Tracked only when in the list or with "block until all apps" (ESP-TS) | **Not touched during either phase**; a flighting key, `RunNontrackedAppsCheckinImmediatelyAfterEsp` = True, started it **20 s after the page closed** (07:12:22), so untracked apps do not wait for the hourly check-in | ⚠️ |
| User-targeted app, system install context, in the list | Tracked in the account setup phase (ESP) | Registered under the user's SID (`./User/Vendor/MSFT/EnrollmentStatusTracking`), detected and installed by SYSTEM in session 0, the page waited for it | ✅ |
| User-install-context app, not in the list | Tracking needs device context and no user-context applicability rules (ESP-TS) | Ran after the page, as the user in session 2: detection, install, detection at 07:13 | ✅ |
| Remediations during the page | Not documented | **None ran during either phase.** HealthScripts fetched both policies at 07:10:02 (account phase); the first detections ran at 07:15, three minutes after the page closed, user and device policies together | ⚠️ |
| `ESP completed` timing | – | Logged at 07:11:22 while USR-W32-BLOCK was still `InProgress` (Completed at 07:12:02); the post-page check-in itself ran at 07:12:22, after the app completed | ⚠️ |
| Writing to ProgramData from user context | – | A user-context script that appends to a file SYSTEM created under `C:\ProgramData\IntuneScriptLab` gets `Access to the path ... is denied`; stderr made the platform script report `Fail` and the remediation `Detect error even if exit code is 0` (`PreRemediationDetectScriptError`), exit 0 in both cases. Grant the folder or write per user | ⚠️ trap |
| Phase bookkeeping | `InstallationState` 1 NotInstalled, 2 InProgress, 3 Completed, 4 Error (ESP-TS) | As documented, `Device\Setup\Apps\Tracking\Sidecar\Win32App_<id>_<ver>` 1 → 2 → 3, the user's apps under the SID key; `ESPTrackingInfo\Diagnostics\Sidecar\<timestamp>` keeps every state change; FirstSync `ApplicationsDuration` is the device phase in seconds (135) and `IsSyncDone=1` appeared with the account phase | ✅ |
| Sign-in with "Require MFA to register or join devices" on | Entra requires MFA for the join | The user-driven Autopilot sign-in of a user with no MFA method stops at "Keep your account secure – Start by getting the app" with **no skip**; sign-in log status 50072, Conditional Access `notApplied`. The Authenticator registration campaign (which has a snooze) is not the cause: excluding the user changed nothing. Turning the toggle off (or replacing it with a Conditional Access policy on the "Register or join devices" action with an exclusion) unblocks it | ⚠️ |
| OOBE sign-in session | – | Expires after ~10 minutes idle: "Sorry, your sign-in timed out. Please sign in again." | ⚠️ |
| Autopilot profile name | Not documented for Graph | `POST windowsAutopilotDeploymentProfiles` with a `-` in `displayName` returns a generic 400; the portal says "Character '-' is not allowed". The name template `ISL%SERIAL%` turned serial `ISL-ESP-01` into `ISLISLESP01`: hyphens are stripped | ⚠️ |
| Windows Hello | Tenant WHfB enrollment configuration "Not configured" | After the account phase the console demanded a Windows Hello PIN with no skip; a test account without an MFA method cannot get past it. Disable WHfB for the lab group or give the account a method | ⚠️ |

**For the tool:** `Get-IntuneAgentLog` names the page's lines (`ScriptEspPhase`, `EspPhase`,
`EspAppsSelected`, `EspAppRegistered`, `EspAppState`, `EspPhaseComplete`, `EspComplete`,
`EspNontrackedCheckin`, `UserlessCheckin`), so `-EventName EspPhase, EspAppRegistered, EspAppState,
EspPhaseComplete` reads a device's page as a timeline; the platform-script and remediation help notes
state where each script type sits relative to the page.

## Assignment sanity

Round 9, 2026-09-28 (`Invoke-AssignmentProbe.ps1`): six SYSTEM remediations with the same scripts and
different assignments, the agent restarted on VM 125 (Entra joined, in ISL-Validation-Devices; its
clock runs seven hours behind UTC) and VM 126 (Entra joined by Autopilot, in ISL-ESP-Devices, the user
`isl-esp` signed in), HealthScripts.log and the probe files read ten minutes later.

| Rule | Documented | Observed | |
|---|---|---|---|
| No assignment | A policy must be assigned to apply (portal) | **Never resolved**: absent from both devices' `ProcessResolvedPolicies` lists and logs; no run, no probe record (ASSIGN-NONE) | ✅ |
| Only an exclusion | Not documented | The same: never resolved on either device (ASSIGN-EXCLONLY) | ⚠️ |
| Include and exclude of the same group | Exclusion wins over inclusion (Intune assignment docs) | **Graph shows only the include**: `POST /assign` with both accepted, `GET /assignments` returns one `groupAssignmentTarget`. VM 125 resolved the policy and inspected its schedule (`inspect hourly schedule for policy <INEX>`, queued with the others) but **the runner never executed it**: the 25 other resolved remediations ran in the following cycle, this one did not in 55 minutes, no probe record. The exclusion holds on the device while the API hides it, so there is nothing to detect after the fact (ASSIGN-INEX) | ⚠️ |
| Run-once schedule in the past | `deviceHealthScriptRunOnceSchedule` date, time (GRAPH-HS) | A device fetching the policy two hours after the time **ran it once at the fetch**: resolved 16:57:55, `will try to execute now` 17:03:24, detection, remediation, detection, and no second run (ASSIGN-PAST2 on VM 126). VM 125 inspected the same shape of schedule as a future time on its slow clock (ASSIGN-PAST): a device clock decides | ⚠️ |
| SYSTEM remediation assigned to a user group | User-targeted policies apply where the user signs in (portal) | Resolved and run on VM 126 under the signed-in member's id (`"UserId":"c3b8cf61..."`, ran 17:02:55, 5 minutes after the fetch, as SYSTEM); never resolved on VM 125, where no member is signed in (ASSIGN-USERGRP) | ✅ |
| Fetch to first run | Not documented | Fetch at the agent start (16:57:55), first run 17:02:55, five minutes later, as in round 1 | ✅ |

**For the tool:** `Test-IntuneDeployedScript` warns about a policy with no assignment or only
exclusions (`IslAssignmentIssue`), notes a run-once schedule whose time has passed
(`IslScheduleIssue`, Information) and a user-context script assigned to a device group (skipped on
Entra registered devices, round 1). An include and an exclude of the same group cannot be seen
after the fact, so it is documented only.

## PowerShell 7 at run time, a built credential, and the drives SYSTEM sees

Round 10, 2026-10-05, VM 125 (Entra joined, Windows PowerShell 5.1.26100.9444): seven SYSTEM
remediations, 64-bit, the agent restarted once. Deployed 05:59 UTC, fetched at the restart, queued
for 06:10; `REM-INSTALL-MODULE` (round 7) had the runner by 06:19 and held it for about an hour, its
60-minute timeout as before, so the seven detections ran at 07:19:05-07:20:31 UTC; Graph's run
states for all seven carry `lastStateUpdateDateTime` 07:22:40. Each row is the device's own result record
(`SideCarPolicies\Scripts\Reports\...\Result`) next to the probe file and Graph `deviceRunStates`.

REM-PS7-SYNTAX (round 1) is the case that does not parse: the detection never starts and exits 1.
These are the cases that do parse.

| Rule | Documented | Observed | |
|---|---|---|---|
| A cmdlet only PowerShell 7 has (`Test-Json`) | Not documented | **The script carries on.** The call writes `The term 'Test-Json' is not recognized` (`CommandNotFoundException`) and the next line runs: output `after cmdlet valid=[]`, `FirstDetectExitCode` 0, `RemediationStatus` 4 (without issues), the error text in `PreRemediationDetectScriptError`, no remediation run, Graph `detectionState success, remediationState skipped` (REM-PS7-CMDLET) | ⚠️ |
| A parameter only PowerShell 7 has (`ConvertFrom-Json -AsHashtable`) | Not documented | The same: `A parameter cannot be found that matches parameter name 'AsHashtable'` (`NamedParameterNotFound`), output `after parameter table=[]`, exit 0, without issues, no remediation (REM-PS7-PARAM) | ⚠️ |
| `ForEach-Object -Parallel` | Not documented | The same: `Parameter set cannot be resolved using the specified named parameters` (`AmbiguousParameterSet`), nothing came out of the pipeline (the reported `items=[1]` is `@($null).Count`), exit 0, without issues, no remediation (REM-PS7-PARALLEL) | ⚠️ |
| A value only PowerShell 7 has (`Out-File -Encoding utf8NoBOM`) | Not documented | The same, and nothing is written: `The argument "utf8NoBOM" does not belong to the set "unknown,string,unicode,bigendianunicode,utf8,utf7,utf32,ascii,default,oem"` (`ParameterArgumentValidationError`), the target file did not exist afterwards (`written=[False]`), exit 0, without issues, no remediation (REM-PS7-ENCODING) | ⚠️ |
| `#Requires -Version 7.0` | The script does not run (PS docs on #Requires) | As documented, and what Intune makes of it: the detection exits 1 without running, stderr `The script 'detect.ps1' cannot be run because it contained a "#requires" statement for Windows PowerShell 7.0` (`ScriptRequiresUnmatchedPSVersion`), no output; the remediation script **runs** (its probe record at 07:19:36), the post-detection fails the same way, `RemediationStatus` 2 (recurred), Graph `detectionState fail, remediationState remediationFailed`. The result record carries `RemediationExitCode` 1 although the remediation ends in `exit 0` and wrote its record; not followed up (REM-PS7-REQUIRES) | ✅ |
| `Get-Credential -Credential` handed a `PSCredential` | Not documented for the agent | **Returns it, no prompt:** `returned=[isl-built] ms=12`, exit 0, nothing on stderr, although the agent launches without `-NonInteractive` (REM-CRED-BUILT). A user name in the same place is the prompting case, which was not run: a prompt holds the runner for the 60-minute timeout (REM-INSTALL-MODULE) | ✅ |
| Drives a SYSTEM script sees | Not documented | **Local volumes, and not the drives the signed-in user mapped.** With a second local volume `D:` on the device and `X:` mapped to a share in the console user's session (`net use` there listed it before the run and again after it), the SYSTEM detection reported `drives=C:\=Fixed,D:\=Fixed X=[False]` (REM-DRIVES-SYS; the fixture is `New-IslDriveFixture.ps1`) | ⚠️ |

**For the tool:** `IslPowerShell7Syntax` kept one evidence string, the parse error's, for all of
these; a parse error and a failed call end in opposite verdicts for a detection (exit 1 and a
remediation run, against the script's own exit 0 and "without issues"). The cmdlet, parameter and
`-Parallel` findings now say the call fails and the script carries on, and cite these experiments;
`#Requires` cites its own; `Out-File -Encoding utf8NoBOM`, listed in the rule but never matched,
is a finding. `IslInteractiveCall` keeps `Get-Credential` an error where it is sure to
prompt and makes `-Credential` with anything but a literal a warning, since a variable there may
hold a credential that is already built, and a note when the script gives the argument no value
that is not one: built by `[pscredential]::new()`, `New-Object`, `Import-Clixml` (which hands back
what `Export-Clixml` wrote, a credential in this idiom), a cast or a typed parameter; the call cannot
prompt and can go. `IslContextIssue` no longer calls every drive letter from
`D:` to `Z:` an unmapped drive: the letter cannot say whether it is a local volume, so the finding
is a note that says which case fails.

## Win32 custom detection scripts

Round 2: ten Win32 apps sharing one `.intunewin` package (an install script that only writes a probe
record), each with a different custom detection script, assigned as *required* to the device group.

| Rule | Documented | Observed | |
|---|---|---|---|
| Win32 apps on Entra registered | IME supports registered/WPJ (IME); app page doesn't restrict (W32) | **Delivered, detected and installed** on the registered device via a device group. The "joined only" wording on the Remediations page does not carry over to Win32 | ✅ |
| Delivery after assignment | Not documented | Push notification (`NotificationIntent: Win32AppWorkload`): first detection script ran **6 seconds** after the assignment call. Apps assigned after the push was processed waited for the next check-in | ⚠️ |
| `isAssigned` on the app | "whether the app is assigned to at least one group" (Graph) | Still `false` 30+ minutes after assignment for every app, including ones already installed on the device. Read `/assignments` instead | ❌ |
| IME restart timing | "restarts immediately, initiating a check-in" (IME) | Start-up applies delays: `Delaying all checkins by 36 s`, then `Delaying PS and Win32 app workload checkins by 147 s` (183 s total) before the first workload check-in. `[Policy] check in interval from cache is : 3600 seconds` | ⚠️ |
| Detected = exit 0 **and** stdout non-empty | Yes (W32) | Exit 0 + `installed` → Detected. Exit 0 with nothing on stdout → **NotDetected** → install ran → still NotDetected → error `0x87D1041C` | ✅ |
| Anything on stderr | Not detected, even with exit 0 + stdout (W32) | `Write-Error` with exit 0 + stdout → AgentExecutor reports `exitCode: -1` to IME → NotDetected | ✅ |
| `Write-Host` as stdout | Not documented | **Counts as stdout** → Detected (host output goes to the redirected console stream) | ⚠️ |
| `Write-Warning` as stderr | Not documented | **Does not count as stderr** → Detected | ⚠️ |
| Exit 1 with stdout | Not detected (W32) | NotDetected | ✅ |
| Unhandled `throw` | Not documented | Exit 1 → NotDetected | ⚠️ |
| Bitness default | 64-bit on 64-bit clients (W32) | `Is64BitProcess=True` with `runAs32Bit=false` | ✅ |
| `runAs32Bit` on the rule | 32-bit (W32) | `Is64BitProcess=False` (`RunAs32Bit: 1` in AppWorkload.log) | ✅ |
| Context | Not stated for detection scripts (W32) | SYSTEM, session 0 (`InstallExRunAs: 1`, "machine session"); cwd `C:\WINDOWS\system32` | ⚠️ |
| Launch | Not documented | `AgentExecutor.exe -powershellDetection <script> ...`; script written to `C:\Program Files (x86)\Microsoft Intune Management Extension\Content\DetectionScripts\<appId>_<ver>.ps1` and deleted after the run | ⚠️ |
| Timeout (detection) | Not documented (W32) | `Powershell execution process timeout milliseconds: 3600000` → **60 minutes** | ⚠️ |
| Encoding (no BOM) | UTF-8 with BOM recommended (W32) | No BOM → decoded as ANSI (`Grüße — ✓` → `GrÃ¼ÃŸe â€" âœ“`), same as scripts and remediations | ✅ trap |
| Encoding (BOM) | UTF-8 with BOM recommended (W32) | BOM kept on disk (`EF BB BF`), literal decoded correctly, app Detected | ✅ |
| Requirement script in user context | `runAsAccount` option exists (W32) | **Ran as the signed-in user** (`<device>\<local user>`, session 2) on the Entra *registered* device, unlike user-context platform scripts. Output `ok` matched → Applicable → app Installed | ✅ / ⚠️ |
| Rule evaluation order | Not documented | **Detection runs before requirement**: `Detection ... Detected @15:15:04`, then `ProcessRequirementRules starts @15:15:04`, then applicability | ⚠️ |
| Reporting latency to Intune | Not documented | `LastModifiedDateTime` in the install-status report was 1–3 minutes after the device finished (re-assigned app: 8 seconds) | ⚠️ |
| `powershell.exe` in install command | Launches 32-bit (W32) | `Is64BitProcess=False`, SYSTEM, launched **directly by `Microsoft.Management.Services.IntuneWindowsAgent.exe`** (not AgentExecutor), cwd = content folder `C:\WINDOWS\IMECache\<appId>_<ver>\`, file bytes unchanged (BOM kept) | ✅ |
| Install timeout | 60 min default (W32) | `Installer process timeout milliseconds: 3600000` | ✅ |
| Processing order | Not documented | Per app: detect → applicability → download → **detect again** → install → detect again; content cache cleaned ~20 s after install | ⚠️ |
| Install status via Graph | `mobileApps/{id}/deviceStatuses` (older docs) | **Gone from beta** (`Resource not found`), as is `reports/getDeviceInstallStatusReport`. Working path: `POST /beta/deviceManagement/reports/exportJobs` with `reportName: DeviceInstallStatusByApp`, then download the CSV (`AppInstallState_loc`, `HexErrorCode`) | ❌ |
| Device-side state | Not documented | `HKLM\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps\<userId>\<appId>_<ver>\` with `ComplianceStateMessage` and `EnforcementStateMessage` JSON (`EnforcementState: 5000`, `ErrorCode: -2016345060` for installed-but-not-detected) | ⚠️ |
