# Round 1 experiments. Each script body is appended to Probe.ps1 before upload.
# Names are prefixed with ISL- in Intune so Invoke-ValidationRound can find and remove them.
#
# Keys:
#   RunAs32Bit / RunAsAccount  Omit to test what Intune defaults to.
#   Bom                        Upload with a UTF-8 BOM (default: no BOM).
#   Question                   What the experiment answers; copied into the results.
#   Schedule                   Remediations: @{ Type = 'RunOnce'|'Daily'; DelayMinutes = n } or @{ Interval = n }
#                              (hourly, the default when omitted).
@{
    Remediations = @(
        # --- Round 11: a remediation that writes to stderr, in user context on the ESP device
        # (ISL-ESP-Devices, -GroupName; the signed-in user must hold an Intune licence, a local
        # account or an unlicensed Entra user gets no user-context policy). Run once each, the
        # date in the past so the agent runs them at its next policy fetch
        @{
            Name         = 'REM-STDERR-EXIT0'
            Question     = 'Remediation writes a cmdlet error to stderr and exits 0: Recurred, or script error'
            RunAs32Bit   = $true
            RunAsAccount = 'user'
            Schedule     = @{ Type = 'RunOnce'; DelayMinutes = -10080 }
            Detection    = @'
Write-ProbeRecord REM-STDERR-EXIT0 detection
$key = 'HKCU:\Software\Microsoft\Siuf\Rules'
$value = (Get-ItemProperty -Path $key -ErrorAction SilentlyContinue).NumberOfSIUFInPeriod
if ($value -eq 0) { Write-Output 'Feedback requests are off'; exit 0 }
Write-Output "Feedback requests are on (value: $value)"
exit 1
'@
            Remediation  = @'
Write-ProbeRecord REM-STDERR-EXIT0 remediation
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Siuf\Rules' -Name NumberOfSIUFInPeriod -Value 0
Write-Output 'Feedback requests turned off'
exit 0
'@
        }
        @{
            Name         = 'REM-STDERR-SILENT'
            Question     = 'The same remediation with the error silenced: exit 0, no stderr, key still missing'
            RunAs32Bit   = $true
            RunAsAccount = 'user'
            Schedule     = @{ Type = 'RunOnce'; DelayMinutes = -10080 }
            Detection    = @'
Write-ProbeRecord REM-STDERR-SILENT detection
$key = 'HKCU:\Software\Microsoft\Siuf\Rules'
$value = (Get-ItemProperty -Path $key -ErrorAction SilentlyContinue).NumberOfSIUFInPeriod
if ($value -eq 0) { Write-Output 'Feedback requests are off'; exit 0 }
Write-Output "Feedback requests are on (value: $value)"
exit 1
'@
            Remediation  = @'
Write-ProbeRecord REM-STDERR-SILENT remediation
$key = 'HKCU:\Software\Microsoft\Siuf\Rules'
Set-ItemProperty -Path $key -Name NumberOfSIUFInPeriod -Value 0 -ErrorAction SilentlyContinue
Write-Output 'Feedback requests turned off'
exit 0
'@
        }
        @{
            Name         = 'REM-DETECT-STDERR-EXIT0'
            Question     = 'Detection writes a cmdlet error to stderr and exits 0: without issues, or detect error'
            RunAs32Bit   = $true
            RunAsAccount = 'user'
            Schedule     = @{ Type = 'RunOnce'; DelayMinutes = -10080 }
            Detection    = @'
Write-ProbeRecord REM-DETECT-STDERR-EXIT0 detection
Get-Item -Path 'C:\does\not\exist'
Write-Output 'Feedback requests are off'
exit 0
'@
            Remediation  = @'
Write-ProbeRecord REM-DETECT-STDERR-EXIT0 remediation; Write-Output 'nothing to do'; exit 0
'@
        }
        # --- Round 8: the Enrollment Status Page. Deployed to ISL-ESP-Devices (ESP-DEV-*) and
        # ISL-ESP-Users (ESP-USR-*) with -GroupName; every script records the ESP's state at run time
        @{
            Name         = 'ESP-DEV-REM-SYS'
            Question     = 'Does a device-targeted SYSTEM remediation run during the device ESP phase, and when'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Detection    = @'
Write-ProbeRecord ESP-DEV-REM-SYS detection; Write-EspState ESP-DEV-REM-SYS detection; exit 0
'@
            Remediation  = 'Write-ProbeRecord ESP-DEV-REM-SYS remediation; exit 0'
        }
        @{
            Name         = 'ESP-USR-REM-USER'
            Question     = 'Does a user-targeted user-context remediation run in the account ESP phase, and when'
            RunAs32Bit   = $false
            RunAsAccount = 'user'
            Detection    = @'
Write-ProbeRecord ESP-USR-REM-USER detection; Write-EspState ESP-USR-REM-USER detection; exit 0
'@
            Remediation  = 'Write-ProbeRecord ESP-USR-REM-USER remediation; exit 0'
        }
        # --- Execution environment -----------------------------------------------------------
        @{
            Name         = 'REM-PROBE-SYS64'
            Question     = 'How IME launches a 64-bit SYSTEM detection script'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Detection    = 'Write-ProbeRecord REM-PROBE-SYS64 detection; Write-Output "probe ok"; exit 0'
            Remediation  = 'Write-ProbeRecord REM-PROBE-SYS64 remediation; exit 0'
        }
        @{
            Name         = 'REM-PROBE-SYS32'
            Question     = 'Does runAs32Bit launch SysWOW64 PowerShell'
            RunAs32Bit   = $true
            RunAsAccount = 'system'
            Detection    = 'Write-ProbeRecord REM-PROBE-SYS32 detection; Write-Output "probe ok"; exit 0'
            Remediation  = 'Write-ProbeRecord REM-PROBE-SYS32 remediation; exit 0'
        }
        @{
            Name         = 'REM-PROBE-USER64'
            Question     = 'How user context is launched (session, profile, env vars)'
            RunAs32Bit   = $false
            RunAsAccount = 'user'
            Detection    = 'Write-ProbeRecord REM-PROBE-USER64 detection; Write-Output "probe ok"; exit 0'
            Remediation  = 'Write-ProbeRecord REM-PROBE-USER64 remediation; exit 0'
        }
        @{
            Name         = 'REM-PROBE-USER32'
            Question     = 'User context in 32-bit'
            RunAs32Bit   = $true
            RunAsAccount = 'user'
            Detection    = 'Write-ProbeRecord REM-PROBE-USER32 detection; Write-Output "probe ok"; exit 0'
            Remediation  = 'Write-ProbeRecord REM-PROBE-USER32 remediation; exit 0'
        }
        @{
            Name        = 'REM-DEFAULTS'
            Question    = 'Defaults when runAs32Bit and runAsAccount are omitted'
            Detection   = 'Write-ProbeRecord REM-DEFAULTS detection; Write-Output "probe ok"; exit 0'
            Remediation = 'Write-ProbeRecord REM-DEFAULTS remediation; exit 0'
        }
        @{
            Name         = 'REM-ENC-BOM'
            Question     = @'
Non-ASCII literal survives when uploaded with a UTF-8 BOM (compare REM-PROBE-SYS64, no BOM)
'@
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Bom          = $true
            Detection    = 'Write-ProbeRecord REM-ENC-BOM detection; Write-Output "Grüße — ✓"; exit 0'
            Remediation  = 'Write-ProbeRecord REM-ENC-BOM remediation; exit 0'
        }

        # --- Status mapping ------------------------------------------------------------------
        @{
            Name         = 'REM-FIX'
            Question     = 'Baseline: detect fails, remediation fixes, post-detection passes'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Detection    = @'
Write-ProbeRecord REM-FIX detection
if (Test-Path -Path 'C:\ProgramData\IntuneScriptLab\REM-FIX.marker') { Write-Output 'marker present'; exit 0 }
Write-Output 'marker missing'
exit 1
'@
            Remediation  = @'
Write-ProbeRecord REM-FIX remediation
New-Item -ItemType File -Path 'C:\ProgramData\IntuneScriptLab\REM-FIX.marker' -Force | Out-Null
Write-Output 'created marker'
exit 0
'@
        }
        @{
            Name         = 'REM-RECUR'
            Question     = 'Remediation exits 0 but post-detection still fails'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Detection    = 'Write-ProbeRecord REM-RECUR detection; Write-Output "still broken"; exit 1'
            Remediation  = 'Write-ProbeRecord REM-RECUR remediation; Write-Output "remediated"; exit 0'
        }
        @{
            Name         = 'REM-REMFAIL'
            Question     = 'Remediation script itself exits non-zero'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Detection    = 'Write-ProbeRecord REM-REMFAIL detection; Write-Output "broken"; exit 1'
            Remediation  = 'Write-ProbeRecord REM-REMFAIL remediation; Write-Error "remediation failed"; exit 1'
        }

        # --- Exit codes: does remediation run? (remediation writes a probe record if it does) --
        @{
            Name         = 'REM-EXIT-2'
            Question     = 'Detection exit 2'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Detection    = 'Write-ProbeRecord REM-EXIT-2 detection; Write-Output "exit two"; exit 2'
            Remediation  = 'Write-ProbeRecord REM-EXIT-2 remediation; exit 0'
        }
        @{
            Name         = 'REM-EXIT-NEG1'
            Question     = 'Detection exit -1'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Detection    = 'Write-ProbeRecord REM-EXIT-NEG1 detection; Write-Output "exit minus one"; exit -1'
            Remediation  = 'Write-ProbeRecord REM-EXIT-NEG1 remediation; exit 0'
        }
        @{
            Name         = 'REM-EXIT-THROW'
            Question     = 'Detection throws (terminating error, no exit)'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Detection    = @'
Write-ProbeRecord REM-EXIT-THROW detection; Write-Output "about to throw"; throw "boom"
'@
            Remediation  = 'Write-ProbeRecord REM-EXIT-THROW remediation; exit 0'
        }
        @{
            Name         = 'REM-EXIT-NONE'
            Question     = 'Detection falls through with no exit statement'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Detection    = 'Write-ProbeRecord REM-EXIT-NONE detection; Write-Output "no exit statement"'
            Remediation  = 'Write-ProbeRecord REM-EXIT-NONE remediation; exit 0'
        }
        @{
            Name         = 'REM-EXIT-ERRNOEXIT'
            Question     = 'Non-terminating error, then fall through with no exit'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Detection    = @'
Write-ProbeRecord REM-EXIT-ERRNOEXIT detection
Get-Item -Path 'C:\does\not\exist'
Write-Output 'after the error'
'@
            Remediation  = 'Write-ProbeRecord REM-EXIT-ERRNOEXIT remediation; exit 0'
        }
        @{
            # Pattern from Microsoft's own sample detection scripts (ref-remediation-scripts)
            Name         = 'REM-RETURN-EXIT'
            Question     = 'return 1 before exit 1 at script scope: does exit 1 ever happen?'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Detection    = @'
Write-ProbeRecord REM-RETURN-EXIT detection; Write-Output "found 1 issue"; return 1; exit 1
'@
            Remediation  = 'Write-ProbeRecord REM-RETURN-EXIT remediation; exit 0'
        }
        @{
            Name         = 'REM-PS7-SYNTAX'
            Question     = 'PowerShell 7-only syntax (ternary): parse error under 5.1'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Detection    = 'Write-Output "parsed"; $x = $true ? 1 : 2; exit 0'
            Remediation  = 'Write-ProbeRecord REM-PS7-SYNTAX remediation; exit 0'
        }

        # --- Output capture ------------------------------------------------------------------
        @{
            Name         = 'REM-OUT-STREAMS'
            Question     = 'Which streams and lines end up in the reported output'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Detection    = @'
Write-ProbeRecord REM-OUT-STREAMS detection
Write-Output 'out-1'
Write-Output 'out-2'
Write-Host 'host-3'
Write-Warning 'warn-4'
Write-Verbose 'verbose-5' -Verbose
Write-Error 'err-6'
[Console]::Error.WriteLine('stderr-7')
Write-Output 'out-8'
exit 0
'@
            Remediation  = 'Write-ProbeRecord REM-OUT-STREAMS remediation; exit 0'
        }
        # Round 3: which streams can be the *reported* line. REM-OUT-STREAMS ended with Write-Output,
        # so it never showed whether Write-Host/Warning/Verbose text reaches the report at all.
        @{
            Name         = 'REM-OUT-HOSTLAST'
            Question     = 'Is Write-Host text reported when it is the last line'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Detection    = @'
Write-ProbeRecord REM-OUT-HOSTLAST detection; Write-Output "out-first"; Write-Host "host-last"; exit 0
'@
            Remediation  = 'Write-ProbeRecord REM-OUT-HOSTLAST remediation; exit 0'
        }
        @{
            Name         = 'REM-OUT-WARNLAST'
            Question     = 'Is Write-Warning text reported when it is the last line'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Detection    = @'
Write-ProbeRecord REM-OUT-WARNLAST detection; Write-Output "out-first"; Write-Warning "warn-last"; exit 0
'@
            Remediation  = 'Write-ProbeRecord REM-OUT-WARNLAST remediation; exit 0'
        }
        @{
            Name         = 'REM-OUT-VERBLAST'
            Question     = 'Is Write-Verbose -Verbose text reported when it is the last line'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Detection    = @'
Write-ProbeRecord REM-OUT-VERBLAST detection; Write-Output "out-first"-Verbose "verbose-last" -Verbose; exit 0
'@
            Remediation  = 'Write-ProbeRecord REM-OUT-VERBLAST remediation; exit 0'
        }
        @{
            Name         = 'REM-OUT-LONG'
            Question     = 'Output truncation point (segments labelled with their end offset)'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Detection    = @'
Write-ProbeRecord REM-OUT-LONG detection
Write-Output (-join (1..60 | ForEach-Object { ('[{0:D5}' -f ($_ * 100)) + ('.' * 93) + ']' }))
exit 0
'@
            Remediation  = 'Write-ProbeRecord REM-OUT-LONG remediation; exit 0'
        }
        @{
            Name         = 'REM-ERR-LONG'
            Question     = 'Error output truncation point'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Detection    = @'
Write-ProbeRecord REM-ERR-LONG detection
[Console]::Error.WriteLine((-join (1..60 | ForEach-Object { ('[{0:D5}' -f ($_ * 100)) + ('.' * 93) + ']' })))
Write-Output 'stdout line'
exit 0
'@
            Remediation  = 'Write-ProbeRecord REM-ERR-LONG remediation; exit 0'
        }
        # Round 5: assignment schedules. The detection always fails so every scheduled run leaves a
        # remediation probe record; the record count over the bake period is the answer.
        #   Schedule   @{ Type = 'RunOnce'|'Daily'; DelayMinutes = n } or @{ Interval = n } (hourly, the default)
        @{
            Name         = 'REM-RUNONCE'
            Question     = 'runOnce schedule: when it runs relative to the scheduled time, and whether it repeats'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Schedule     = @{ Type = 'RunOnce'; DelayMinutes = 20 }
            Detection    = 'Write-ProbeRecord REM-RUNONCE detection; Write-Output "always broken"; exit 1'
            Remediation  = 'Write-ProbeRecord REM-RUNONCE remediation; exit 0'
        }
        # Round 6: a daily schedule and a detect-only assignment (runRemediationScript = false)
        @{
            Name         = 'REM-DAILY'
            Question     = 'Daily schedule: first run relative to the scheduled time, then one run a day'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Schedule     = @{ Type = 'Daily'; DelayMinutes = 15 }
            Detection    = 'Write-ProbeRecord REM-DAILY detection; Write-Output "always broken"; exit 1'
            Remediation  = 'Write-ProbeRecord REM-DAILY remediation; exit 0'
        }
        @{
            Name         = 'REM-DETECTONLY'
            Question     = 'no remediation script uploaded: detection fails hourly, nothing else runs; the status'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            DetectOnly   = $true
            Detection    = 'Write-ProbeRecord REM-DETECTONLY detection; Write-Output "issue found"; exit 1'
        }
        # Round 7: what a script can rely on under the agent - modules, the gallery, the execution
        # policy - and whether a script over the documented 200 KB limit runs at all. The detection
        # output (2,048 characters, last line) carries the observation; exit 0 keeps it a one-off.
        @{
            Name         = 'REM-PSMODULEPATH'
            Question     = 'Which module paths SYSTEM sees, and how many modules are available'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Detection    = @'
Write-ProbeRecord REM-PSMODULEPATH detection
Write-Output ("paths=" + $env:PSModulePath + " count=" + @(Get-Module -ListAvailable).Count)
exit 0
'@
            Remediation  = 'Write-ProbeRecord REM-PSMODULEPATH remediation; exit 0'
        }
        @{
            Name         = 'REM-EXECPOLICY'
            Question     = 'Which execution policy each scope has when the agent runs a script'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Detection    = @'
Write-ProbeRecord REM-EXECPOLICY detection
Write-Output ((Get-ExecutionPolicy -List | ForEach-Object { "$($_.Scope)=$($_.ExecutionPolicy)" }) -join ";")
exit 0
'@
            Remediation  = 'Write-ProbeRecord REM-EXECPOLICY remediation; exit 0'
        }
        @{
            Name         = 'REM-INSTALL-MODULE'
            Question     = 'Can a SYSTEM script reach the gallery and install a module (NuGet bootstrap)'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Detection    = @'
Write-ProbeRecord REM-INSTALL-MODULE detection
$out = @()
try { $null = Find-Module -Name PSSQLite -Repository PSGallery -ErrorAction Stop; $out += 'find=ok' }
catch { $out += 'find=' + $_.Exception.Message }
try {
    Install-Module -Name PSSQLite -Scope CurrentUser -Force -ErrorAction Stop
    $out += 'install=ok:' + (Get-Module PSSQLite -ListAvailable | Select-Object -First 1).ModuleBase
}
catch { $out += 'install=' + $_.Exception.Message }
Write-Output ($out -join ' | ')
exit 0
'@
            Remediation  = 'Write-ProbeRecord REM-INSTALL-MODULE remediation; exit 0'
        }
        @{
            Name         = 'REM-REQUIRES-MODULE'
            Question     = 'What the agent reports when #Requires names a module the device lacks'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Detection    = @'
#Requires -Modules IslNoSuchModule
Write-ProbeRecord REM-REQUIRES-MODULE detection
Write-Output "ran anyway"
exit 0
'@
            Remediation  = 'Write-ProbeRecord REM-REQUIRES-MODULE remediation; exit 0'
        }
        @{
            Name         = 'REM-SIZE-250KB'
            Question     = 'Does a 250 KB remediation (over the documented 200 KB) run on the device'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            PadKB        = 250
            Detection    = 'Write-ProbeRecord REM-SIZE-250KB detection; Write-Output "big script ran"; exit 0'
            Remediation  = 'Write-ProbeRecord REM-SIZE-250KB remediation; exit 0'
        }
        # Round 10: what Windows PowerShell 5.1 does under the agent with the PowerShell 7 cmdlets,
        # parameters and values that parse (REM-PS7-SYNTAX is the one that does not), whether
        # Get-Credential prompts when it is handed a credential that is already built, and which
        # drives a SYSTEM script sees while the signed-in user has one mapped. The remediation
        # writes a probe record if it runs; the detection's last line carries the observation.
        @{
            Name         = 'REM-PS7-CMDLET'
            Question     = 'A cmdlet only PowerShell 7 has (Test-Json): does the detection stop or carry on'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Detection    = @'
Write-ProbeRecord REM-PS7-CMDLET detection
Write-Output 'before'
$valid = '{}' | Test-Json
Write-Output "after cmdlet valid=[$valid]"
exit 0
'@
            Remediation  = 'Write-ProbeRecord REM-PS7-CMDLET remediation; exit 0'
        }
        @{
            Name         = 'REM-PS7-PARAM'
            Question     = 'A parameter only PowerShell 7 has (ConvertFrom-Json -AsHashtable): stop or carry on'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Detection    = @'
Write-ProbeRecord REM-PS7-PARAM detection
Write-Output 'before'
$table = '{"a":1}' | ConvertFrom-Json -AsHashtable
Write-Output "after parameter table=[$($table.a)]"
exit 0
'@
            Remediation  = 'Write-ProbeRecord REM-PS7-PARAM remediation; exit 0'
        }
        @{
            Name         = 'REM-PS7-PARALLEL'
            Question     = 'ForEach-Object -Parallel under 5.1: stop or carry on'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Detection    = @'
Write-ProbeRecord REM-PS7-PARALLEL detection
Write-Output 'before'
$items = 1..2 | ForEach-Object -Parallel { $_ }
Write-Output "after parallel items=[$(@($items).Count)]"
exit 0
'@
            Remediation  = 'Write-ProbeRecord REM-PS7-PARALLEL remediation; exit 0'
        }
        @{
            Name         = 'REM-PS7-ENCODING'
            Question     = 'A value only PowerShell 7 has (Out-File -Encoding utf8NoBOM): is the file written'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Detection    = @'
Write-ProbeRecord REM-PS7-ENCODING detection
$target = 'C:\ProgramData\IntuneScriptLab\REM-PS7-ENCODING.txt'
Remove-Item -Path $target -ErrorAction SilentlyContinue
'x' | Out-File -FilePath $target -Encoding utf8NoBOM
Write-Output "after encoding written=[$(Test-Path -Path $target)]"
exit 0
'@
            Remediation  = 'Write-ProbeRecord REM-PS7-ENCODING remediation; exit 0'
        }
        @{
            Name         = 'REM-PS7-REQUIRES'
            Question     = 'What the agent reports for #Requires -Version 7.0'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Detection    = @'
#Requires -Version 7.0
Write-ProbeRecord REM-PS7-REQUIRES detection
Write-Output "ran anyway"
exit 0
'@
            Remediation  = 'Write-ProbeRecord REM-PS7-REQUIRES remediation; exit 0'
        }
        @{
            Name         = 'REM-CRED-BUILT'
            Question     = 'Get-Credential -Credential with a PSCredential object: does it prompt or return'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Detection    = @'
Write-ProbeRecord REM-CRED-BUILT detection
$secure = New-Object -TypeName System.Security.SecureString
foreach ($char in 'not-a-secret'.ToCharArray()) { $secure.AppendChar($char) }
$built = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList 'isl-built', $secure
$stopwatch = [Diagnostics.Stopwatch]::StartNew()
$returned = Get-Credential -Credential $built
Write-Output "returned=[$($returned.UserName)] ms=$($stopwatch.ElapsedMilliseconds)"
exit 0
'@
            Remediation  = 'Write-ProbeRecord REM-CRED-BUILT remediation; exit 0'
        }
        @{
            Name         = 'REM-DRIVES-SYS'
            Question     = 'Which drives SYSTEM sees while the signed-in user has X: mapped to a share'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Detection    = @'
Write-ProbeRecord REM-DRIVES-SYS detection
$drives = [IO.DriveInfo]::GetDrives() | ForEach-Object { "$($_.Name)=$($_.DriveType)" }
Write-Output ("drives=" + ($drives -join ',') + " X=[" + (Test-Path -Path 'X:\') + "]")
exit 0
'@
            Remediation  = 'Write-ProbeRecord REM-DRIVES-SYS remediation; exit 0'
        }
    )


    # Win32 apps: all share one package (Win32Install.ps1); only the detection rule differs.
    # Detection = "installed" means the app is left alone; "not detected" makes IME run the install
    # command (which writes an 'install' probe record) and then detect again.
    #   Requirement    Optional PowerShell requirement rule: @{ Script; RunAsAccount; RunAs32Bit; OperationType;
    #                  Operator; ComparisonValue }. Defaults: system, 64-bit, string equal 'ok'.
    #   Round 4 (W32-REQ-*): the detection always exits 1, so whether the install probe fires shows
    #   whether the requirement rule passed; the requirement script's own probe shows how it ran.
    Win32Apps = @(
        # --- Round 8: the Enrollment Status Page. Marker detections (the shared install writes
        # <name>.installed) so each app is "installed" once its install ran; the two BLOCK apps and
        # the user one go into the ESP profile's selected (blocking) list, NOBLOCK stays out of it
        @{
            Name      = 'ESP-DEV-W32-BLOCK1'
            Question  = 'Blocking device app: installed during the device ESP phase, and in what order'
            Detection = @'
Write-EspState ESP-DEV-W32-BLOCK1 detection
if (Test-Path 'C:\ProgramData\IntuneScriptLab\ESP-DEV-W32-BLOCK1.installed') {
    Write-ProbeRecord ESP-DEV-W32-BLOCK1 detection; Write-Output 'installed'; exit 0
}
Write-ProbeRecord ESP-DEV-W32-BLOCK1 detection; exit 1
'@
        }
        @{
            Name      = 'ESP-DEV-W32-BLOCK2'
            Question  = 'Second blocking device app: ordering against the first'
            Detection = @'
Write-EspState ESP-DEV-W32-BLOCK2 detection
if (Test-Path 'C:\ProgramData\IntuneScriptLab\ESP-DEV-W32-BLOCK2.installed') {
    Write-ProbeRecord ESP-DEV-W32-BLOCK2 detection; Write-Output 'installed'; exit 0
}
Write-ProbeRecord ESP-DEV-W32-BLOCK2 detection; exit 1
'@
        }
        @{
            Name      = 'ESP-DEV-W32-NOBLOCK'
            Question  = 'Required device app outside the blocking list: during the ESP or only after it'
            Detection = @'
Write-EspState ESP-DEV-W32-NOBLOCK detection
if (Test-Path 'C:\ProgramData\IntuneScriptLab\ESP-DEV-W32-NOBLOCK.installed') {
    Write-ProbeRecord ESP-DEV-W32-NOBLOCK detection; Write-Output 'installed'; exit 0
}
Write-ProbeRecord ESP-DEV-W32-NOBLOCK detection; exit 1
'@
        }
        @{
            Name      = 'ESP-USR-W32-BLOCK'
            Question  = 'Blocking user-targeted app (system install context): installed in the account ESP phase'
            Detection = @'
Write-EspState ESP-USR-W32-BLOCK detection
if (Test-Path 'C:\ProgramData\IntuneScriptLab\ESP-USR-W32-BLOCK.installed') {
    Write-ProbeRecord ESP-USR-W32-BLOCK detection; Write-Output 'installed'; exit 0
}
Write-ProbeRecord ESP-USR-W32-BLOCK detection; exit 1
'@
        }
        @{
            Name           = 'ESP-USR-W32-USERCTX'
            Question       = 'User-targeted app, user install context: installed as the user in the account phase'
            InstallContext = 'user'
            Detection      = @'
Write-EspState ESP-USR-W32-USERCTX detection
if (Test-Path 'C:\ProgramData\IntuneScriptLab\ESP-USR-W32-USERCTX.installed') {
    Write-ProbeRecord ESP-USR-W32-USERCTX detection; Write-Output 'installed'; exit 0
}
Write-ProbeRecord ESP-USR-W32-USERCTX detection; exit 1
'@
        }
        @{
            Name      = 'W32-DET-PROBE'
            Question  = 'Baseline: exit 0 + stdout = installed; how detection scripts are launched'
            Detection = 'Write-ProbeRecord W32-DET-PROBE detection; Write-Output "installed"; exit 0'
        }
        @{
            Name      = 'W32-DET-NOOUT'
            Question  = 'Exit 0 with no stdout: documented as NOT detected'
            Detection = 'Write-ProbeRecord W32-DET-NOOUT detection; exit 0'
        }
        @{
            Name      = 'W32-DET-STDERR'
            Question  = 'Exit 0 + stdout + Write-Error: documented as NOT detected'
            Detection = @'
Write-ProbeRecord W32-DET-STDERR detection; Write-Output "installed"; Write-Error "oops"; exit 0
'@
        }
        @{
            Name      = 'W32-DET-HOST'
            Question  = 'Does Write-Host count as stdout'
            Detection = 'Write-ProbeRecord W32-DET-HOST detection; Write-Host "installed"; exit 0'
        }
        @{
            Name      = 'W32-DET-WARN'
            Question  = 'Does Write-Warning count as stderr'
            Detection = @'
Write-ProbeRecord W32-DET-WARN detection; Write-Output "installed"; Write-Warning "careful"; exit 0
'@
        }
        @{
            Name      = 'W32-DET-EXIT1'
            Question  = 'Exit 1 with stdout: not detected'
            Detection = 'Write-ProbeRecord W32-DET-EXIT1 detection; Write-Output "installed"; exit 1'
        }
        @{
            Name      = 'W32-DET-THROW'
            Question  = 'Unhandled throw after writing stdout'
            Detection = 'Write-ProbeRecord W32-DET-THROW detection; Write-Output "installed"; throw "boom"'
        }
        @{
            Name       = 'W32-DET-32'
            Question   = 'runAs32Bit on a detection rule'
            RunAs32Bit = $true
            Detection  = 'Write-ProbeRecord W32-DET-32 detection; Write-Output "installed"; exit 0'
        }
        @{
            Name      = 'W32-DET-BOM'
            Question  = 'Detection script uploaded with UTF-8 BOM (docs recommend it)'
            Bom       = $true
            Detection = 'Write-ProbeRecord W32-DET-BOM detection; Write-Output "Grüße — ✓"; exit 0'
        }
        @{
            Name        = 'W32-REQ-USER'
            Question    = 'Requirement script in user context: does it run on this device'
            Detection   = 'Write-ProbeRecord W32-REQ-USER detection; Write-Output "installed"; exit 0'
            Requirement = @{
                RunAsAccount = 'user'
                Script       = 'Write-ProbeRecord W32-REQ-USER requirement; Write-Output "ok"'
            }
        }
        @{
            Name        = 'W32-REQ-BASE'
            Question    = 'Requirement baseline: SYSTEM, 64-bit, output ok equals ok; how it is launched'
            Detection   = 'Write-ProbeRecord W32-REQ-BASE detection; exit 1'
            Requirement = @{ Script = 'Write-ProbeRecord W32-REQ-BASE requirement; Write-Output "ok"' }
        }
        @{
            Name        = 'W32-REQ-32'
            Question    = 'Requirement with runAs32Bit'
            Detection   = 'Write-ProbeRecord W32-REQ-32 detection; exit 1'
            Requirement = @{
                RunAs32Bit = $true
                Script     = 'Write-ProbeRecord W32-REQ-32 requirement; Write-Output "ok"'
            }
        }
        @{
            Name        = 'W32-REQ-CASE'
            Question    = 'String comparison case sensitivity: output OK against value ok'
            Detection   = 'Write-ProbeRecord W32-REQ-CASE detection; exit 1'
            Requirement = @{ Script = 'Write-ProbeRecord W32-REQ-CASE requirement; Write-Output "OK"' }
        }
        @{
            Name        = 'W32-REQ-LASTLINE'
            Question    = 'Multi-line output: is the last line compared (first, ok)'
            Detection   = 'Write-ProbeRecord W32-REQ-LASTLINE detection; exit 1'
            Requirement = @{
                Script = 'Write-ProbeRecord W32-REQ-LASTLINE requirement; Write-Output "first"; Write-Output "ok"'
            }
        }
        @{
            Name        = 'W32-REQ-FIRSTLINE'
            Question    = 'Multi-line output: is the first line compared (ok, second)'
            Detection   = 'Write-ProbeRecord W32-REQ-FIRSTLINE detection; exit 1'
            Requirement = @{
                Script = @'
Write-ProbeRecord W32-REQ-FIRSTLINE requirement; Write-Output "ok"; Write-Output "second"
'@
            }
        }
        @{
            Name        = 'W32-REQ-HOST'
            Question    = 'Does Write-Host count as requirement output'
            Detection   = 'Write-ProbeRecord W32-REQ-HOST detection; exit 1'
            Requirement = @{ Script = 'Write-ProbeRecord W32-REQ-HOST requirement; Write-Host "ok"' }
        }
        @{
            Name        = 'W32-REQ-TRAIL'
            Question    = 'Is the output trimmed: "ok   " against ok'
            Detection   = 'Write-ProbeRecord W32-REQ-TRAIL detection; exit 1'
            Requirement = @{ Script = 'Write-ProbeRecord W32-REQ-TRAIL requirement; Write-Output "ok   "' }
        }
        @{
            Name        = 'W32-REQ-EXIT1'
            Question    = 'Output ok but exit 1: docs say only exit 0 is evaluated'
            Detection   = 'Write-ProbeRecord W32-REQ-EXIT1 detection; exit 1'
            Requirement = @{ Script = 'Write-ProbeRecord W32-REQ-EXIT1 requirement; Write-Output "ok"; exit 1' }
        }
        @{
            Name        = 'W32-REQ-STDERR'
            Question    = 'Output ok plus Write-Error with exit 0'
            Detection   = 'Write-ProbeRecord W32-REQ-STDERR detection; exit 1'
            Requirement = @{
                Script = @'
Write-ProbeRecord W32-REQ-STDERR requirement; Write-Output "ok"; Write-Error "oops"; exit 0
'@
            }
        }
        @{
            Name        = 'W32-REQ-NOOUT'
            Question    = 'No output at all against string equal ok'
            Detection   = 'Write-ProbeRecord W32-REQ-NOOUT detection; exit 1'
            Requirement = @{ Script = 'Write-ProbeRecord W32-REQ-NOOUT requirement; exit 0' }
        }
        @{
            Name        = 'W32-REQ-NOTEQ'
            Question    = 'String notEqual: output ok against bad'
            Detection   = 'Write-ProbeRecord W32-REQ-NOTEQ detection; exit 1'
            Requirement = @{
                Operator        = 'notEqual'
                ComparisonValue = 'bad'
                Script          = 'Write-ProbeRecord W32-REQ-NOTEQ requirement; Write-Output "ok"'
            }
        }
        @{
            Name        = 'W32-REQ-INT'
            Question    = 'Integer greaterThan: output 5 against 3'
            Detection   = 'Write-ProbeRecord W32-REQ-INT detection; exit 1'
            Requirement = @{
                OperationType   = 'integer'
                Operator        = 'greaterThan'
                ComparisonValue = '3'
                Script          = 'Write-ProbeRecord W32-REQ-INT requirement; Write-Output 5'
            }
        }
        @{
            Name        = 'W32-REQ-INTBAD'
            Question    = 'Integer rule with non-numeric output: five against 3'
            Detection   = 'Write-ProbeRecord W32-REQ-INTBAD detection; exit 1'
            Requirement = @{
                OperationType   = 'integer'
                Operator        = 'greaterThan'
                ComparisonValue = '3'
                Script          = 'Write-ProbeRecord W32-REQ-INTBAD requirement; Write-Output "five"'
            }
        }
        @{
            Name        = 'W32-REQ-FLOAT'
            Question    = 'Float greaterThan: output 1.5 against 1.25'
            Detection   = 'Write-ProbeRecord W32-REQ-FLOAT detection; exit 1'
            Requirement = @{
                OperationType   = 'float'
                Operator        = 'greaterThan'
                ComparisonValue = '1.25'
                Script          = 'Write-ProbeRecord W32-REQ-FLOAT requirement; Write-Output "1.5"'
            }
        }
        @{
            Name        = 'W32-REQ-VER'
            Question    = 'Version greaterThanOrEqual: 2.10.0 against 2.9.0 (a string compare would fail)'
            Detection   = 'Write-ProbeRecord W32-REQ-VER detection; exit 1'
            Requirement = @{
                OperationType   = 'version'
                Operator        = 'greaterThanOrEqual'
                ComparisonValue = '2.9.0'
                Script          = 'Write-ProbeRecord W32-REQ-VER requirement; Write-Output "2.10.0"'
            }
        }
        @{
            Name        = 'W32-REQ-BOOL'
            Question    = 'Boolean equal: $true (prints True) against true'
            Detection   = 'Write-ProbeRecord W32-REQ-BOOL detection; exit 1'
            Requirement = @{
                OperationType   = 'boolean'
                Operator        = 'equal'
                ComparisonValue = 'true'
                Script          = 'Write-ProbeRecord W32-REQ-BOOL requirement; Write-Output $true'
            }
        }
        @{
            Name        = 'W32-REQ-DATE'
            Question    = 'DateTime greaterThan: 2026-01-15 against 2026-01-01'
            Detection   = 'Write-ProbeRecord W32-REQ-DATE detection; exit 1'
            Requirement = @{
                OperationType   = 'dateTime'
                Operator        = 'greaterThan'
                ComparisonValue = '2026-01-01T00:00:00Z'
                Script          = 'Write-ProbeRecord W32-REQ-DATE requirement; Write-Output "2026-01-15"'
            }
        }

        # --- Round 5: file, registry and MSI rules -------------------------------------------
        # Fixtures.ps1 (run by -Action Prepare) creates what these rules look at. With no detection
        # script, "detected" shows as an Installed app with no install probe record; "not detected"
        # shows as an install probe record followed by 0x87D1041C (still not detected). Pairs of
        # true/false cases prove a type is really evaluated rather than always true.
        #   DetectionRules / RequirementRules  Arrays of rule specs (see GraphRules.ps1): Type File,
        #                                      Registry, ProductCode or Script.
        #   Intent                             Assignment intent: required (default) or uninstall.
        #   EnforceSignatureCheck              On the Detection script rule.
        @{
            Name           = 'W32-FILE-EXISTS'
            Question       = 'File exists rule on a present file'
            DetectionRules = @(@{
                    Type = 'File'; Path = 'C:\ProgramData\IntuneScriptLab\Fixtures'
                    FileOrFolderName = 'present.txt'
                    OperationType = 'exists'
                })
        }
        @{
            Name           = 'W32-FILE-MISSING'
            Question       = 'File exists rule on a missing file (false case)'
            DetectionRules = @(@{
                    Type = 'File'; Path = 'C:\ProgramData\IntuneScriptLab\Fixtures'
                    FileOrFolderName = 'missing.txt'
                    OperationType = 'exists'
                })
        }
        @{
            Name           = 'W32-FILE-NOTEXIST'
            Question       = 'File doesNotExist rule on a missing file'
            DetectionRules = @(@{
                    Type = 'File'; Path = 'C:\ProgramData\IntuneScriptLab\Fixtures'
                    FileOrFolderName = 'missing.txt'
                    OperationType = 'doesNotExist'
                })
        }
        @{
            Name           = 'W32-FILE-NOTEXIST-FALSE'
            Question       = 'File doesNotExist rule on a present file (false case)'
            DetectionRules = @(@{
                    Type = 'File'; Path = 'C:\ProgramData\IntuneScriptLab\Fixtures'
                    FileOrFolderName = 'present.txt'
                    OperationType = 'doesNotExist'
                })
        }
        @{
            Name           = 'W32-FILE-VER-GE'
            Question       = 'File version 10.0.26100.x greaterThanOrEqual 9.0: yes as a version, no as a string'
            DetectionRules = @(@{
                    Type = 'File'; Path = 'C:\ProgramData\IntuneScriptLab\Fixtures'
                    FileOrFolderName = 'versioned.exe'
                    OperationType = 'version'; Operator = 'greaterThanOrEqual'; ComparisonValue = '9.0'
                })
        }
        @{
            Name           = 'W32-FILE-VER-LT'
            Question       = 'File version 10.0.26100.x lessThan 9.0: no as a version, yes as a string'
            DetectionRules = @(@{
                    Type = 'File'; Path = 'C:\ProgramData\IntuneScriptLab\Fixtures'
                    FileOrFolderName = 'versioned.exe'
                    OperationType = 'version'; Operator = 'lessThan'; ComparisonValue = '9.0'
                })
        }
        @{
            Name           = 'W32-FILE-SIZE-EQ'
            Question       = 'sizeInMB equal 2 on a 2 MiB file'
            DetectionRules = @(@{
                    Type = 'File'; Path = 'C:\ProgramData\IntuneScriptLab\Fixtures'
                    FileOrFolderName = 'big.bin'
                    OperationType = 'sizeInMB'; Operator = 'equal'; ComparisonValue = '2'
                })
        }
        @{
            Name           = 'W32-FILE-SIZE-GT'
            Question       = 'sizeInMB greaterThan 2 on a 2 MiB file (false case; also whether MB means MiB)'
            DetectionRules = @(@{
                    Type = 'File'; Path = 'C:\ProgramData\IntuneScriptLab\Fixtures'
                    FileOrFolderName = 'big.bin'
                    OperationType = 'sizeInMB'; Operator = 'greaterThan'; ComparisonValue = '2'
                })
        }
        @{
            Name           = 'W32-FILE-DATE-GT'
            Question       = 'modifiedDate greaterThan 2024-01-01 on a file modified 2024-06-15'
            DetectionRules = @(@{
                    Type = 'File'; Path = 'C:\ProgramData\IntuneScriptLab\Fixtures'
                    FileOrFolderName = 'present.txt'
                    OperationType = 'modifiedDate'; Operator = 'greaterThan'
                    ComparisonValue = '2024-01-01T00:00:00Z'
                })
        }
        @{
            Name           = 'W32-FILE-DATE-LT'
            Question       = 'modifiedDate lessThan 2024-01-01 on a file modified 2024-06-15 (false case)'
            DetectionRules = @(@{
                    Type = 'File'; Path = 'C:\ProgramData\IntuneScriptLab\Fixtures'
                    FileOrFolderName = 'present.txt'
                    OperationType = 'modifiedDate'; Operator = 'lessThan'
                    ComparisonValue = '2024-01-01T00:00:00Z'
                })
        }
        @{
            Name           = 'W32-FILE-PF-32'
            Question       = '%ProgramFiles% with check32BitOn64System: does it expand to Program Files (x86)'
            DetectionRules = @(@{
                    Type = 'File'; Path = '%ProgramFiles%\IntuneScriptLab'
                    FileOrFolderName = 'x86only.txt'
                    OperationType = 'exists'; Check32BitOn64System = $true
                })
        }
        @{
            Name           = 'W32-FILE-PF-64'
            Question       = '%ProgramFiles% without check32BitOn64System against a Program Files (x86)-only file'
            DetectionRules = @(@{
                    Type = 'File'; Path = '%ProgramFiles%\IntuneScriptLab'
                    FileOrFolderName = 'x86only.txt'
                    OperationType = 'exists'; Check32BitOn64System = $false
                })
        }
        @{
            Name           = 'W32-REG-KEY-EXISTS'
            Question       = 'Registry key exists (no value name)'
            DetectionRules = @(@{
                    Type = 'Registry'; KeyPath = 'HKEY_LOCAL_MACHINE\SOFTWARE\IntuneScriptLab'
                    OperationType = 'exists'
                })
        }
        @{
            Name           = 'W32-REG-KEY-MISSING'
            Question       = 'Registry key exists on a missing key (false case)'
            DetectionRules = @(@{
                    Type = 'Registry'; KeyPath = 'HKEY_LOCAL_MACHINE\SOFTWARE\IntuneScriptLab\Nope'
                    OperationType = 'exists'
                })
        }
        @{
            Name           = 'W32-REG-KEY-NOTEXIST'
            Question       = 'Registry key doesNotExist on a missing key'
            DetectionRules = @(@{
                    Type = 'Registry'; KeyPath = 'HKEY_LOCAL_MACHINE\SOFTWARE\IntuneScriptLab\Nope'
                    OperationType = 'doesNotExist'
                })
        }
        @{
            Name           = 'W32-REG-VAL-EXISTS'
            Question       = 'Registry value exists'
            DetectionRules = @(@{
                    Type = 'Registry'; KeyPath = 'HKEY_LOCAL_MACHINE\SOFTWARE\IntuneScriptLab'
                    ValueName = 'Name'
                    OperationType = 'exists'
                })
        }
        @{
            Name           = 'W32-REG-STR-EQ'
            Question       = 'Registry string equal, exact case'
            DetectionRules = @(@{
                    Type = 'Registry'; KeyPath = 'HKEY_LOCAL_MACHINE\SOFTWARE\IntuneScriptLab'
                    ValueName = 'Name'
                    OperationType = 'string'; Operator = 'equal'; ComparisonValue = 'IntuneScriptLab'
                })
        }
        @{
            Name           = 'W32-REG-STR-CASE'
            Question       = 'Registry string equal, different case (case-insensitive like script rules?)'
            DetectionRules = @(@{
                    Type = 'Registry'; KeyPath = 'HKEY_LOCAL_MACHINE\SOFTWARE\IntuneScriptLab'
                    ValueName = 'Name'
                    OperationType = 'string'; Operator = 'equal'; ComparisonValue = 'intunescriptlab'
                })
        }
        @{
            Name           = 'W32-REG-STR-NE'
            Question       = 'Registry string equal against a different value (false case)'
            DetectionRules = @(@{
                    Type = 'Registry'; KeyPath = 'HKEY_LOCAL_MACHINE\SOFTWARE\IntuneScriptLab'
                    ValueName = 'Name'
                    OperationType = 'string'; Operator = 'equal'; ComparisonValue = 'other'
                })
        }
        @{
            Name           = 'W32-REG-INT-GT'
            Question       = 'Registry integer greaterThan 40 on DWORD 42'
            DetectionRules = @(@{
                    Type = 'Registry'; KeyPath = 'HKEY_LOCAL_MACHINE\SOFTWARE\IntuneScriptLab'
                    ValueName = 'Build'
                    OperationType = 'integer'; Operator = 'greaterThan'; ComparisonValue = '40'
                })
        }
        @{
            Name           = 'W32-REG-INT-GT-FALSE'
            Question       = 'Registry integer greaterThan 50 on DWORD 42 (false case)'
            DetectionRules = @(@{
                    Type = 'Registry'; KeyPath = 'HKEY_LOCAL_MACHINE\SOFTWARE\IntuneScriptLab'
                    ValueName = 'Build'
                    OperationType = 'integer'; Operator = 'greaterThan'; ComparisonValue = '50'
                })
        }
        @{
            Name           = 'W32-REG-INT-ONSZ'
            Question       = 'Registry integer greaterThan 40 on a REG_SZ holding 42: parsed, or type mismatch'
            DetectionRules = @(@{
                    Type = 'Registry'; KeyPath = 'HKEY_LOCAL_MACHINE\SOFTWARE\IntuneScriptLab'
                    ValueName = 'BuildText'
                    OperationType = 'integer'; Operator = 'greaterThan'; ComparisonValue = '40'
                })
        }
        @{
            Name           = 'W32-REG-VER-GE'
            Question       = 'Registry version greaterThanOrEqual 9.0 on REG_SZ 10.0.1 (string trap)'
            DetectionRules = @(@{
                    Type = 'Registry'; KeyPath = 'HKEY_LOCAL_MACHINE\SOFTWARE\IntuneScriptLab'
                    ValueName = 'Version'
                    OperationType = 'version'; Operator = 'greaterThanOrEqual'; ComparisonValue = '9.0'
                })
        }
        @{
            Name           = 'W32-REG-VER-LT'
            Question       = 'Registry version lessThan 9.0 on REG_SZ 10.0.1 (false case)'
            DetectionRules = @(@{
                    Type = 'Registry'; KeyPath = 'HKEY_LOCAL_MACHINE\SOFTWARE\IntuneScriptLab'
                    ValueName = 'Version'
                    OperationType = 'version'; Operator = 'lessThan'; ComparisonValue = '9.0'
                })
        }
        @{
            Name           = 'W32-REG-VIEW-64'
            Question       = 'View value read from the 64-bit view (check32BitOn64System off): 64'
            DetectionRules = @(@{
                    Type = 'Registry'; KeyPath = 'HKEY_LOCAL_MACHINE\SOFTWARE\IntuneScriptLab'
                    ValueName = 'View'
                    OperationType = 'string'; Operator = 'equal'; ComparisonValue = '64'
                    Check32BitOn64System = $false
                })
        }
        @{
            Name           = 'W32-REG-VIEW-32ON64'
            Question       = 'Same rule with check32BitOn64System on: the WOW6432Node key holds 32, so 64 is false'
            DetectionRules = @(@{
                    Type = 'Registry'; KeyPath = 'HKEY_LOCAL_MACHINE\SOFTWARE\IntuneScriptLab'
                    ValueName = 'View'
                    OperationType = 'string'; Operator = 'equal'; ComparisonValue = '64'
                    Check32BitOn64System = $true
                })
        }
        @{
            Name           = 'W32-REG-VIEW-32'
            Question       = 'check32BitOn64System on, expecting the WOW6432Node value 32'
            DetectionRules = @(@{
                    Type = 'Registry'; KeyPath = 'HKEY_LOCAL_MACHINE\SOFTWARE\IntuneScriptLab'
                    ValueName = 'View'
                    OperationType = 'string'; Operator = 'equal'; ComparisonValue = '32'
                    Check32BitOn64System = $true
                })
        }
        @{
            Name           = 'W32-MSI-EXISTS'
            Question       = 'MSI product code rule without a version operator on an installed 64-bit product'
            DetectionRules = @(@{ Type = 'ProductCode'; ProductCode = '{FBE4D84C-C935-4F54-B96F-49316CEB5149}' })
        }
        @{
            Name           = 'W32-MSI-VER-GE'
            Question       = 'MSI product version 110.0.2 greaterThanOrEqual 99.0.0 (string trap: "110" < "99")'
            DetectionRules = @(@{
                    Type = 'ProductCode'; ProductCode = '{FBE4D84C-C935-4F54-B96F-49316CEB5149}'
                    ProductVersionOperator = 'greaterThanOrEqual'; ProductVersion = '99.0.0'
                })
        }
        @{
            Name           = 'W32-MSI-VER-GT-FALSE'
            Question       = 'MSI product version 110.0.2 greaterThan 200.0.0 (false case)'
            DetectionRules = @(@{
                    Type = 'ProductCode'; ProductCode = '{FBE4D84C-C935-4F54-B96F-49316CEB5149}'
                    ProductVersionOperator = 'greaterThan'; ProductVersion = '200.0.0'
                })
        }
        @{
            Name           = 'W32-MSI-MISSING'
            Question       = 'MSI product code rule on a product that is not installed (false case)'
            DetectionRules = @(@{ Type = 'ProductCode'; ProductCode = '{00000000-1111-2222-3333-444444444444}' })
        }
        @{
            Name           = 'W32-MSI-32BIT'
            Question       = 'MSI product code rule on a 32-bit product (Intune Management Extension, WOW6432Node)'
            DetectionRules = @(@{ Type = 'ProductCode'; ProductCode = '{7ECACCD0-8601-4884-8860-7A4ADF4ED814}' })
        }
        @{
            Name           = 'W32-MULTI-ONEFALSE'
            Question       = 'Two detection rules, one true and one false: all must match, so not detected'
            DetectionRules = @(
                @{
                    Type = 'File'; Path = 'C:\ProgramData\IntuneScriptLab\Fixtures'
                    FileOrFolderName = 'present.txt'
                    OperationType = 'exists'
                }
                @{
                    Type = 'File'; Path = 'C:\ProgramData\IntuneScriptLab\Fixtures'
                    FileOrFolderName = 'missing.txt'
                    OperationType = 'exists'
                }
            )
        }
        @{
            Name           = 'W32-MULTI-BOTHTRUE'
            Question       = 'Two detection rules, both true: detected'
            DetectionRules = @(
                @{
                    Type = 'File'; Path = 'C:\ProgramData\IntuneScriptLab\Fixtures'
                    FileOrFolderName = 'present.txt'
                    OperationType = 'exists'
                }
                @{
                    Type = 'Registry'; KeyPath = 'HKEY_LOCAL_MACHINE\SOFTWARE\IntuneScriptLab'
                    ValueName = 'Name'
                    OperationType = 'string'; Operator = 'equal'; ComparisonValue = 'IntuneScriptLab'
                }
            )
        }
        # Requirement rules: the detection always exits 1, so the install probe fires only when the
        # requirement is met (as in round 4)
        @{
            Name             = 'W32-RREQ-FILE-MET'
            Question         = 'File requirement rule on a present file: applicable, install runs'
            Detection        = 'Write-ProbeRecord W32-RREQ-FILE-MET detection; exit 1'
            RequirementRules = @(@{
                    Type = 'File'; Path = 'C:\ProgramData\IntuneScriptLab\Fixtures'
                    FileOrFolderName = 'present.txt'
                    OperationType = 'exists'
                })
        }
        @{
            Name             = 'W32-RREQ-FILE-UNMET'
            Question         = 'File requirement rule on a missing file: not applicable, and how it is reported'
            Detection        = 'Write-ProbeRecord W32-RREQ-FILE-UNMET detection; exit 1'
            RequirementRules = @(@{
                    Type = 'File'; Path = 'C:\ProgramData\IntuneScriptLab\Fixtures'
                    FileOrFolderName = 'missing.txt'
                    OperationType = 'exists'
                })
        }
        @{
            Name             = 'W32-RREQ-REG-MET'
            Question         = 'Registry requirement rule, string equal: applicable'
            Detection        = 'Write-ProbeRecord W32-RREQ-REG-MET detection; exit 1'
            RequirementRules = @(@{
                    Type = 'Registry'; KeyPath = 'HKEY_LOCAL_MACHINE\SOFTWARE\IntuneScriptLab'
                    ValueName = 'Name'
                    OperationType = 'string'; Operator = 'equal'; ComparisonValue = 'IntuneScriptLab'
                })
        }
        @{
            Name             = 'W32-RREQ-REG-UNMET'
            Question         = 'Registry requirement rule, string equal against a different value: not applicable'
            Detection        = 'Write-ProbeRecord W32-RREQ-REG-UNMET detection; exit 1'
            RequirementRules = @(@{
                    Type = 'Registry'; KeyPath = 'HKEY_LOCAL_MACHINE\SOFTWARE\IntuneScriptLab'
                    ValueName = 'Name'
                    OperationType = 'string'; Operator = 'equal'; ComparisonValue = 'other'
                })
        }
        @{
            Name                  = 'W32-DET-SIGCHECK'
            Question              = 'Unsigned script with enforceSignatureCheck: does it run, what is reported'
            EnforceSignatureCheck = $true
            Detection             = @'
Write-ProbeRecord W32-DET-SIGCHECK detection; Write-Output "installed"; exit 0
'@
        }
        @{
            # Detection says "installed" until the uninstall command drops the marker file
            Name      = 'W32-UNINSTALL'
            Question  = 'Intent uninstall: detect, run the uninstall command, detect again'
            Intent    = 'uninstall'
            Detection = @'
if (Test-Path -Path 'C:\ProgramData\IntuneScriptLab\W32-UNINSTALL.uninstalled') {
    Write-ProbeRecord W32-UNINSTALL detection-after; exit 1
}
Write-ProbeRecord W32-UNINSTALL detection; Write-Output 'installed'; exit 0
'@
        }

        # --- Round 6: requirements, filters, context, relationships, MSI ----------------------
        #   Requirements     Base requirement properties by Graph name (minimumSupportedWindowsRelease,
        #                    allowedArchitectures, minimumFreeDiskSpaceInMB, minimumMemoryInMB,
        #                    minimumNumberOfProcessors, minimumCpuSpeedInMHz).
        #   Filter           @{ Rule = '(device.deviceName -eq "X")'; Mode = 'include'|'exclude' }.
        #   InstallContext   installExperience.runAsAccount: system (default) or user.
        #   DependsOn        @{ App = '<experiment>'; Type = 'autoInstall'|'detect' }; Assign = $false on
        #                    the child leaves it unassigned so only the relationship can install it.
        #   Supersedes       @{ App = '<experiment>'; Type = 'update'|'replace' }; deploy the old app first
        #                    (-Name 'W32-SUP-OLD-*'), let it install, then the new one (-Name 'W32-SUP-NEW-*').
        #   Package          @{ Type = 'Msi'; Url; FileName; Sha256 }: a real installer instead of the shared
        #                    script package; install/uninstall commands default to msiexec, the detection
        #                    to the package's product code unless DetectionRules is given.
        # Marker detections read <Experiment>.installed, which Win32Install.ps1 creates on install and
        # removes on uninstall.
        @{
            Name         = 'W32-REQ-OS-24H2'
            Question     = 'minimumSupportedWindowsRelease Windows11_24H2 on a 24H2 device: applicable'
            Detection    = 'Write-ProbeRecord W32-REQ-OS-24H2 detection; exit 1'
            Requirements = @{ minimumSupportedWindowsRelease = 'Windows11_24H2' }
        }
        @{
            Name         = 'W32-REQ-ARCH-ARM64'
            Question     = 'allowedArchitectures arm64 only on an x64 device: how it is reported'
            Detection    = 'Write-ProbeRecord W32-REQ-ARCH-ARM64 detection; exit 1'
            Requirements = @{ allowedArchitectures = 'arm64' }
        }
        @{
            Name         = 'W32-REQ-DISK'
            Question     = 'minimumFreeDiskSpaceInMB far above the disk: how it is reported'
            Detection    = 'Write-ProbeRecord W32-REQ-DISK detection; exit 1'
            Requirements = @{ minimumFreeDiskSpaceInMB = 100000000 }
        }
        @{
            Name         = 'W32-REQ-MEM'
            Question     = 'minimumMemoryInMB far above the RAM: how it is reported'
            Detection    = 'Write-ProbeRecord W32-REQ-MEM detection; exit 1'
            Requirements = @{ minimumMemoryInMB = 1000000 }
        }
        @{
            Name         = 'W32-REQ-CPU'
            Question     = 'minimumNumberOfProcessors 64: how it is reported'
            Detection    = 'Write-ProbeRecord W32-REQ-CPU detection; exit 1'
            Requirements = @{ minimumNumberOfProcessors = 64 }
        }
        @{
            Name      = 'W32-FILTER-INCLUDE'
            Question  = 'Include filter on the joined device name: only that device gets the app'
            Detection = 'Write-ProbeRecord W32-FILTER-INCLUDE detection; exit 1'
            Filter    = @{ Rule = '(device.deviceName -eq "KRBETYP-AIEPVQ5")'; Mode = 'include' }
        }
        @{
            Name      = 'W32-FILTER-EXCLUDE'
            Question  = 'Exclude filter on the joined device name: only the registered device gets the app'
            Detection = 'Write-ProbeRecord W32-FILTER-EXCLUDE detection; exit 1'
            Filter    = @{ Rule = '(device.deviceName -eq "KRBETYP-AIEPVQ5")'; Mode = 'exclude' }
        }
        @{
            Name           = 'W32-USER-INSTALL'
            Question       = 'Install context user: who runs the detection and the install, on both join types'
            InstallContext = 'user'
            Detection      = 'Write-ProbeRecord W32-USER-INSTALL detection; exit 1'
        }
        @{
            Name      = 'W32-DEP-CHILD'
            Question  = 'Dependency child, not assigned: installed only through the parent relationship'
            Assign    = $false
            Detection = @'
if (Test-Path 'C:\ProgramData\IntuneScriptLab\W32-DEP-CHILD.installed') {
    Write-ProbeRecord W32-DEP-CHILD detection; Write-Output 'installed'; exit 0
}
Write-ProbeRecord W32-DEP-CHILD detection; exit 1
'@
        }
        @{
            Name      = 'W32-DEP-PARENT'
            Question  = 'autoInstall dependency: child installs first, then the parent'
            DependsOn = @{ App = 'W32-DEP-CHILD'; Type = 'autoInstall' }
            Detection = @'
if (Test-Path 'C:\ProgramData\IntuneScriptLab\W32-DEP-PARENT.installed') {
    Write-ProbeRecord W32-DEP-PARENT detection; Write-Output 'installed'; exit 0
}
Write-ProbeRecord W32-DEP-PARENT detection; exit 1
'@
        }
        @{
            Name      = 'W32-DEPD-CHILD'
            Question  = 'Detect-only dependency child, never installed'
            Assign    = $false
            Detection = @'
if (Test-Path 'C:\ProgramData\IntuneScriptLab\W32-DEPD-CHILD.installed') {
    Write-ProbeRecord W32-DEPD-CHILD detection; Write-Output 'installed'; exit 0
}
Write-ProbeRecord W32-DEPD-CHILD detection; exit 1
'@
        }
        @{
            Name      = 'W32-DEPD-PARENT'
            Question  = 'detect dependency with the child absent: parent must not install; how it is reported'
            DependsOn = @{ App = 'W32-DEPD-CHILD'; Type = 'detect' }
            Detection = @'
if (Test-Path 'C:\ProgramData\IntuneScriptLab\W32-DEPD-PARENT.installed') {
    Write-ProbeRecord W32-DEPD-PARENT detection; Write-Output 'installed'; exit 0
}
Write-ProbeRecord W32-DEPD-PARENT detection; exit 1
'@
        }
        @{
            Name      = 'W32-SUP-OLD-A'
            Question  = 'Superseded app (update): installed first, then left in place by the update'
            Detection = @'
if (Test-Path 'C:\ProgramData\IntuneScriptLab\W32-SUP-OLD-A.installed') {
    Write-ProbeRecord W32-SUP-OLD-A detection; Write-Output 'installed'; exit 0
}
Write-ProbeRecord W32-SUP-OLD-A detection; exit 1
'@
        }
        @{
            Name      = 'W32-SUP-OLD-B'
            Question  = 'Superseded app (replace): installed first, then uninstalled by the replacement'
            Detection = @'
if (Test-Path 'C:\ProgramData\IntuneScriptLab\W32-SUP-OLD-B.installed') {
    Write-ProbeRecord W32-SUP-OLD-B detection; Write-Output 'installed'; exit 0
}
Write-ProbeRecord W32-SUP-OLD-B detection; exit 1
'@
        }
        @{
            Name       = 'W32-SUP-NEW-A'
            Question   = 'Supersedence type update: does the old app stay, and what runs in which order'
            Supersedes = @{ App = 'W32-SUP-OLD-A'; Type = 'update' }
            Detection  = @'
if (Test-Path 'C:\ProgramData\IntuneScriptLab\W32-SUP-NEW-A.installed') {
    Write-ProbeRecord W32-SUP-NEW-A detection; Write-Output 'installed'; exit 0
}
Write-ProbeRecord W32-SUP-NEW-A detection; exit 1
'@
        }
        @{
            Name       = 'W32-SUP-NEW-B'
            Question   = 'Supersedence type replace: is the old app uninstalled first'
            Supersedes = @{ App = 'W32-SUP-OLD-B'; Type = 'replace' }
            Detection  = @'
if (Test-Path 'C:\ProgramData\IntuneScriptLab\W32-SUP-NEW-B.installed') {
    Write-ProbeRecord W32-SUP-NEW-B detection; Write-Output 'installed'; exit 0
}
Write-ProbeRecord W32-SUP-NEW-B detection; exit 1
'@
        }
        @{
            Name     = 'W32-MSI-7ZIP'
            Question = 'A real MSI: msiInformation from the package, msiexec commands, product code detection'
            Package  = @{
                Type     = 'Msi'
                Url      = 'https://www.7-zip.org/a/7z2409-x64.msi'
                FileName = '7z2409-x64.msi'
            }
        }
    )

    PlatformScripts = @(
        # --- Round 8: the Enrollment Status Page (see the Remediations section)
        @{
            Name         = 'ESP-DEV-PS-SYS'
            Question     = 'Does a device-targeted SYSTEM platform script run in the device ESP phase (untracked)'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Script       = 'Write-ProbeRecord ESP-DEV-PS-SYS run; Write-EspState ESP-DEV-PS-SYS run; exit 0'
        }
        @{
            Name         = 'ESP-DEV-PS-USER'
            Question     = 'Does a device-targeted user-context platform script run during the account ESP phase'
            RunAs32Bit   = $false
            RunAsAccount = 'user'
            Script       = 'Write-ProbeRecord ESP-DEV-PS-USER run; Write-EspState ESP-DEV-PS-USER run; exit 0'
        }
        @{
            Name         = 'ESP-USR-PS-USER'
            Question     = 'Does a user-targeted user-context platform script run during the account ESP phase'
            RunAs32Bit   = $false
            RunAsAccount = 'user'
            Script       = 'Write-ProbeRecord ESP-USR-PS-USER run; Write-EspState ESP-USR-PS-USER run; exit 0'
        }
        @{
            Name         = 'PS-PROBE-SYS64'
            Question     = 'How IME launches a 64-bit SYSTEM platform script'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Script       = 'Write-ProbeRecord PS-PROBE-SYS64 run; Write-Output "probe ok"; exit 0'
        }
        @{
            Name         = 'PS-PROBE-SYS32'
            Question     = 'Platform script with runAs32Bit'
            RunAs32Bit   = $true
            RunAsAccount = 'system'
            Script       = 'Write-ProbeRecord PS-PROBE-SYS32 run; Write-Output "probe ok"; exit 0'
        }
        @{
            Name         = 'PS-PROBE-USER'
            Question     = 'Platform script in user context'
            RunAs32Bit   = $false
            RunAsAccount = 'user'
            Script       = 'Write-ProbeRecord PS-PROBE-USER run; Write-Output "probe ok"; exit 0'
        }
        @{
            Name     = 'PS-DEFAULTS'
            Question = 'Defaults when runAs32Bit and runAsAccount are omitted'
            Script   = 'Write-ProbeRecord PS-DEFAULTS run; Write-Output "probe ok"; exit 0'
        }
        @{
            Name         = 'PS-FAIL'
            Question     = 'Retry behaviour: one probe record per attempt'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Script       = 'Write-ProbeRecord PS-FAIL run; Write-Error "deliberate failure"; exit 1'
        }
        @{
            Name         = 'PS-OUT'
            Question     = 'What platform scripts report as result/output, and truncation'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Script       = @'
Write-ProbeRecord PS-OUT run
Write-Output 'out-1'
Write-Output 'out-2'
Write-Host 'host-3'
Write-Output (-join (1..60 | ForEach-Object { ('[{0:D5}' -f ($_ * 100)) + ('.' * 93) + ']' }))
exit 0
'@
        }
        # Round 6: a second failing script, deployed without restarting the registered device's agent, to
        # see when policy is fetched on its own and how the three runs are spaced
        @{
            Name         = 'PS-FAIL-2'
            Question     = 'Natural policy fetch cadence without an agent restart, and the retry spacing'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            Script       = 'Write-ProbeRecord PS-FAIL-2 run; Write-Error "deliberate failure"; exit 1'
        }
        # Round 7: a platform script well over the documented 200 KB (the API took 512 KB)
        @{
            Name         = 'PS-SIZE-500KB'
            Question     = 'Does a 500 KB platform script run on the device'
            RunAs32Bit   = $false
            RunAsAccount = 'system'
            PadKB        = 500
            Script       = 'Write-ProbeRecord PS-SIZE-500KB run; Write-Output "big script ran"; exit 0'
        }
    )

}
