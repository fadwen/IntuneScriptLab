function Invoke-IslScriptRun {
    <#
    .SYNOPSIS
        Runs one script the way the Intune Management Extension does.

    .DESCRIPTION
        Observed launch (PS-PROBE-*, REM-PROBE-*, Win32 log): AgentExecutor starts
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File <script> with no -NonInteractive,
        working directory C:\WINDOWS\system32, the script copied to a cache folder, stdout and
        stderr redirected to files, and kills the process at the timeout. Console output goes
        through the OEM code page, which is what mangles non-ASCII in Intune's reports.

        Context System runs the same command through a scheduled task as NT AUTHORITY\SYSTEM in
        session 0, like the agent. User runs it directly, or, with -Credential, through a scheduled
        task as that account (in its own session when it has one, the way the agent runs
        user-context scripts as the signed-in user: REM-PROBE-USER64). For another account the
        cache lives under ProgramData rather than the caller's temp folder, with that account
        granted Modify on it, since the account has to read the copy and write its output there.

        Deviation: stdin is an empty stream rather than a hidden console, so a prompt returns
        immediately instead of hanging for the timeout. Test-IntuneScript's IslInteractiveCall
        rule is the check for that.

    .PARAMETER Path
        The script to run.

    .PARAMETER Architecture
        The host to run it in: x86, x64 or arm64 (Get-IslHostPath).

    .PARAMETER Context
        User, the default, or System.

    .PARAMETER Credential
        Runs it as this account, Context User only. Needs an elevated session.

    .PARAMETER LogonType
        How the credential's task logs on: Auto, the default, Interactive or Password
        (Invoke-IslProcess).

    .PARAMETER Phase
        What the run is, such as detect, remediate or script, for the result and the name of the
        copy in the cache.

    .PARAMETER TimeoutSeconds
        How long the script may run, 300 by default.

    .PARAMETER WorkingDirectory
        The folder the script runs in, System32 by default, as the agent runs it.

    .EXAMPLE
        Invoke-IslScriptRun -Path .\Detect.ps1 -Architecture 'x64' -Phase 'detect'

        The exit code and output of the detection script run as the current user in the 64-bit host.

    .INPUTS
        None.

    .OUTPUTS
        IntuneScriptLab.RunResult.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.RunResult')]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateSet('x86', 'x64', 'arm64')]
        [string]$Architecture,

        [ValidateSet('User', 'System')]
        [string]$Context = 'User',

        # Run as this account (Context User); needs an elevated session
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential,

        [ValidateSet('Auto', 'Interactive', 'Password')]
        [string]$LogonType = 'Auto',

        # What the run is, for the result and the cache file name: detect, remediate, script
        [string]$Phase = 'script',

        [ValidateRange(1, 86400)]
        [int]$TimeoutSeconds = 300,

        [string]$WorkingDirectory = (Join-Path -Path $env:WINDIR -ChildPath 'System32')
    )

    # No host for the architecture, or no script at the path: nothing has been started yet
    try {
        $hostInfo = Get-IslHostPath -Architecture $Architecture
        $source = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # Like IMECache: the script runs from a copy, so $PSScriptRoot is not the source folder. The
    # run folder and the copy are this function's own bookkeeping. The command that asked for the
    # run has had its -WhatIf and its -Confirm answered before it called; with a preference still
    # in effect here, the copy would be skipped and the host started on a file that is not there.
    # For the same reason a copy that fails ends the function here: the catch below sees it only
    # with -ErrorAction Stop
    $cache = $null
    try {
        # Another account's folder is under ProgramData, closed to other users (New-IslRunFolder)
        $runAccount = if ($Credential) { $Credential.UserName } else { $null }
        $cache = New-IslRunFolder -Account $runAccount
        $scriptCopy = Join-Path -Path $cache -ChildPath "$Phase.ps1"
        Copy-Item -LiteralPath $source -Destination $scriptCopy -ErrorAction Stop @script:IslInternal
        $processSplat = @{
            FilePath = $hostInfo.Path
            Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptCopy`""
            WorkingDirectory = $WorkingDirectory
            WorkFolder = $cache
            Context = $Context
            TimeoutSeconds = $TimeoutSeconds
        }
        if ($Credential) {
            $processSplat.Credential = $Credential
            $processSplat.LogonType = $LogonType
        }
        $run = Invoke-IslProcess @processSplat
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    } finally {
        if ($cache) {
            Remove-Item -LiteralPath $cache -Recurse -Force -ErrorAction SilentlyContinue @script:IslInternal
        }
    }

    [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.RunResult'
        Phase = $Phase
        ScriptPath = $source
        Host = $hostInfo.Path
        Architecture = $Architecture
        Context = $Context
        RunAs = "$($run.UserName) ($($run.LogonType))"
        UserName = $run.UserName
        LogonType = $run.LogonType
        ExitCode = $run.ExitCode
        TimedOut = $run.TimedOut
        StdOut = $run.StdOut
        StdErr = $run.StdErr
        Duration = $run.Duration
    }
}
