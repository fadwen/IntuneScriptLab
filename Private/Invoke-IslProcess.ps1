function Invoke-IslProcess {
    <#
    .SYNOPSIS
        Runs an executable as the current user, as SYSTEM or as another account, capturing its result.

    .DESCRIPTION
        User: a direct child process with stdin closed and both output streams read through
        the OEM code page, as a console-less powershell.exe writes them. Started from PowerShell 7,
        the child gets the session's PSModulePath without PowerShell 7's own folders
        (Get-IslDesktopModulePath), so a powershell.exe loads its own modules.

        System: a one-shot scheduled task registered for NT AUTHORITY\SYSTEM (session 0, the same
        place the Intune agent runs scripts) whose action is cmd.exe redirecting the command's
        output to files in the work folder. Needs an elevated session. The task is removed
        afterwards; a timeout stops the task and kills anything still holding the work folder's id
        in its command line.

        Credential (with Context User): the same task registered for that account. When the account
        holds a logon session the task's logon type is Interactive and it runs inside that session,
        which is where the agent runs user-context scripts (the signed-in user's session, session 2,
        UserInteractive true: REM-PROBE-USER64). Without a session the task is registered with the
        password, "run whether user is logged on or not", and runs in session 0 with the account's
        profile loaded but no interactive session. -LogonType forces one or the other. Needs an
        elevated session either way, and the account needs write access to the work folder.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.ProcessResult')]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [string]$Arguments = '',

        [Parameter(Mandatory)]
        [string]$WorkingDirectory,

        # Scratch folder for the task modes' output files; its leaf name doubles as the run id
        [Parameter(Mandatory)]
        [string]$WorkFolder,

        [ValidateSet('User', 'System')]
        [string]$Context = 'User',

        # Run as this account through a scheduled task (Context User only)
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential,

        # How the credential's task logs on: Auto picks Interactive when the account has a session
        [ValidateSet('Auto', 'Interactive', 'Password')]
        [string]$LogonType = 'Auto',

        [ValidateRange(1, 86400)]
        [int]$TimeoutSeconds = 300,

        # Which cmd.exe hosts the task: 64-bit for explicit host paths, 32-bit to make bare
        # 'powershell.exe' resolve to SysWOW64 the way the agent's own x86 process does
        [ValidateSet('x64', 'x86')]
        [string]$LauncherBitness = 'x64'
    )

    $oem = Get-IslOemEncoding
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $timedOut = $false
    $useTask = $Context -eq 'System' -or $null -ne $Credential
    $logon = 'Direct'
    $userName = if ($env:USERDOMAIN) { "$env:USERDOMAIN\$env:USERNAME" } else { [Environment]::UserName }

    if (-not $useTask) {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $FilePath
        $startInfo.Arguments = $Arguments
        $startInfo.WorkingDirectory = $WorkingDirectory
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.StandardOutputEncoding = $oem
        $startInfo.StandardErrorEncoding = $oem
        # From PowerShell 7 the child would inherit PowerShell 7's module folders and a
        # powershell.exe would load its Microsoft.PowerShell.* modules from them
        if ($PSVersionTable.PSEdition -eq 'Core') {
            $desktopModulePath = Get-IslDesktopModulePath
            if ($desktopModulePath) { $startInfo.Environment['PSModulePath'] = $desktopModulePath }
            else { $null = $startInfo.Environment.Remove('PSModulePath') }
        }

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        $null = $process.Start()
        $process.StandardInput.Close()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $timedOut = $true
            & taskkill.exe /PID $process.Id /T /F 2>&1 | Out-Null
            $process.WaitForExit()
        }
        $stopwatch.Stop()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $exitCode = $process.ExitCode
        $process.Dispose()
    }
    else {
        $runId = Split-Path -Path $WorkFolder -Leaf
        $outFile = Join-Path -Path $WorkFolder -ChildPath 'stdout.txt'
        $errFile = Join-Path -Path $WorkFolder -ChildPath 'stderr.txt'
        $exitFile = Join-Path -Path $WorkFolder -ChildPath 'exitcode.txt'
        $use32BitLauncher = $LauncherBitness -eq 'x86' -and [Environment]::Is64BitOperatingSystem
        $cmdFolder = if ($use32BitLauncher) { 'SysWOW64' } else { 'System32' }
        $cmd = Join-Path -Path (Join-Path -Path $env:WINDIR -ChildPath $cmdFolder) -ChildPath 'cmd.exe'
        # Outer quotes are stripped by cmd /C; !ERRORLEVEL! needs /V:ON to expand after the command runs
        $wrapper = ("/V:ON /C `"`"$FilePath`" $Arguments 1>`"$outFile`" 2>`"$errFile`" & echo !ERRORLEVEL! " +
            ">`"$exitFile`"`"")

        $taskName = "IntuneScriptLab-$runId"
        $action = New-ScheduledTaskAction -Execute $cmd -Argument $wrapper -WorkingDirectory $WorkingDirectory
        $taskSettingsSplat = @{
            AllowStartIfOnBatteries    = $true
            DontStopIfGoingOnBatteries = $true
            StartWhenAvailable         = $true
            ExecutionTimeLimit         = [TimeSpan]::FromSeconds($TimeoutSeconds + 60)
        }
        $registerTaskSplat = @{
            TaskName    = $taskName
            Action      = $action
            Settings    = New-ScheduledTaskSettingsSet @taskSettingsSplat
            Force       = $true
            ErrorAction = 'Stop'
        }
        if ($Context -eq 'System') {
            $logon = 'ServiceAccount'
            $userName = 'NT AUTHORITY\SYSTEM'
            $principalSplat = @{ UserId = 'SYSTEM'; LogonType = 'ServiceAccount'; RunLevel = 'Highest' }
            $registerTaskSplat.Principal = New-ScheduledTaskPrincipal @principalSplat
            $refusal = ('Context System registers a scheduled task that runs as SYSTEM, which this session ' +
                'cannot do (run elevated)')
        }
        else {
            $userName = $Credential.UserName
            # The session is found by the account's SID when Windows resolves the name; an Entra
            # account's Windows name is neither the sign-in name nor a part of it. A name Windows
            # cannot resolve is matched as text against the session owner's name
            $resolved = Resolve-IslAccount -Name $userName
            $account = if ($userName -match '\\') { ($userName -split '\\')[-1] }
            elseif ($userName -match '@') { ($userName -split '@')[0] }
            else { $userName }
            $sessions = @(Get-IslLogonSession | Where-Object {
                    if ($resolved) { $_.Sid -eq $resolved.Sid } else { $_.UserName -eq $account }
                })
            $logon = if ($LogonType -ne 'Auto') { $LogonType }
            elseif ($sessions.Count -gt 0) { 'Interactive' }
            else { 'Password' }
            Write-Verbose "Task for ${userName}: logon type $logon, $($sessions.Count) session(s) found"
            if ($logon -eq 'Interactive') {
                # The scheduler takes an Entra account by its Windows name only
                $principalName = if ($resolved) { $resolved.Name } else { $userName }
                $principalSplat = @{ UserId = $principalName; LogonType = 'Interactive'; RunLevel = 'Limited' }
                $registerTaskSplat.Principal = New-ScheduledTaskPrincipal @principalSplat
            }
            else {
                # The scheduler takes an Entra account by its Windows name only, here too
                $registerTaskSplat.User = if ($resolved) { $resolved.Name } else { $userName }
                $registerTaskSplat.Password = $Credential.GetNetworkCredential().Password
                $registerTaskSplat.RunLevel = 'Limited'
            }
            $refusal = ("Running as $userName registers a scheduled task for that account, which this " +
                'session cannot do (run elevated; a stored-password logon also needs the right password)')
        }
        # Registering the task is the real test of rights: a role check misjudges accounts (build
        # agents, for one) that are not in Administrators yet can do this
        try {
            $null = Register-ScheduledTask @registerTaskSplat
        }
        catch {
            throw "${refusal}: $($_.Exception.Message)"
        }
        try {
            Start-ScheduledTask -TaskName $taskName
            $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
            $neverStartedAfter = (Get-Date).AddSeconds(5)
            $launchFailure = $null
            while (-not (Test-Path -LiteralPath $exitFile) -and (Get-Date) -lt $deadline) {
                Start-Sleep -Milliseconds 250
                # A task the scheduler refuses to start (a logon type the account is not granted)
                # ends at once with a result code and never writes the exit file: read it rather
                # than waiting for the timeout. 267009 is "running", 267011 "has not run yet"
                $info = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue
                if (-not $info) { continue }
                $state = (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue).State
                if ($info.LastTaskResult -notin 0, 267009, 267011 -and $state -ne 'Running') {
                    $launchFailure = [uint32]$info.LastTaskResult
                    break
                }
                # The refusal does not always come with a code: on the lab device a stored-password
                # task for an account without the batch logon right sits Ready, "has not run yet",
                # with no error anywhere. Five seconds of that after Start-ScheduledTask is the same
                # failure
                $neverStarted = $info.LastTaskResult -eq 267011 -and $state -eq 'Ready'
                if ($neverStarted -and (Get-Date) -gt $neverStartedAfter) {
                    $launchFailure = [uint32]267011
                    break
                }
            }
            if ($launchFailure) {
                $code = '0x{0:X8}' -f $launchFailure
                $never = if ($code -eq '0x00041303') { 'the scheduler never launched it: ' } else { '' }
                $hint = if ($resolved -and $resolved.Name -like 'AzureAD\*' -and $logon -eq 'Password') {
                    # On the lab device the right made no difference for an Entra account: the task
                    # sat Ready, "has not run yet", with the right granted (Findings, "The harness
                    # as another account")
                    " ($($never)a stored-password task did not start for a Microsoft Entra account " +
                    'on the lab device, with or without the "Log on as a batch job" right; sign the ' +
                    'account in and run while it holds a session)'
                }
                elseif ($code -eq '0x80070569' -or ($code -eq '0x00041303' -and $logon -eq 'Password')) {
                    " ($($never)the account is not granted the ""Log on as a batch job"" right a " +
                    'stored-password task needs; grant it in the local security policy, or run while the ' +
                    'account holds a session)'
                }
                else { '' }
                throw "The scheduled task for $userName did not start: $code$hint"
            }
            if (-not (Test-Path -LiteralPath $exitFile)) {
                $timedOut = $true
                Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
                # Anything the task started carries the run id in its command line
                $cimInstanceSplat = @{
                    ClassName   = 'Win32_Process'
                    Filter      = "CommandLine LIKE '%$runId%'"
                    ErrorAction = 'SilentlyContinue'
                }
                Get-CimInstance @cimInstanceSplat |
                    Where-Object { $_.ProcessId -ne $PID } |
                    ForEach-Object { & taskkill.exe /PID $_.ProcessId /T /F 2>&1 | Out-Null }
            }
            else {
                # cmd writes the exit file before its own redirections are flushed; give it a moment
                $settleUntil = (Get-Date).AddSeconds(5)
                do {
                    Start-Sleep -Milliseconds 200
                    $state = (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue).State
                }
                while ($state -eq 'Running' -and (Get-Date) -lt $settleUntil)
            }
        }
        finally {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        }
        $stopwatch.Stop()
        $stdout = if (Test-Path -LiteralPath $outFile) {
            $oem.GetString([System.IO.File]::ReadAllBytes($outFile))
        }
        else { '' }
        $stderr = if (Test-Path -LiteralPath $errFile) {
            $oem.GetString([System.IO.File]::ReadAllBytes($errFile))
        }
        else { '' }
        $exitText = if (Test-Path -LiteralPath $exitFile) {
            (Get-Content -LiteralPath $exitFile -Raw).Trim()
        }
        else { '' }
        $exitCode = if ($exitText -match '^-?\d+$') { [int]$exitText } else { $null }
    }

    [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.ProcessResult'
        ExitCode  = if ($timedOut) { $null } else { $exitCode }
        TimedOut  = $timedOut
        StdOut    = $stdout
        StdErr    = $stderr
        Duration  = $stopwatch.Elapsed
        Context   = $Context
        UserName  = $userName
        LogonType = $logon
    }
}
