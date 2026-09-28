function Invoke-IslScriptRun {
    <#
    .SYNOPSIS
        Runs one script the way the Intune Management Extension does and captures the raw result.

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

    $hostInfo = Get-IslHostPath -Architecture $Architecture
    $source = (Resolve-Path -LiteralPath $Path).ProviderPath

    # Like IMECache: the script runs from a copy, so $PSScriptRoot is not the source folder
    $runId = [guid]::NewGuid().ToString('N')
    $cache = if ($Credential) {
        Join-Path -Path $env:ProgramData -ChildPath "IntuneScriptLab\Runs\$runId"
    }
    else {
        Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "IntuneScriptLab\$runId"
    }
    $null = New-Item -ItemType Directory -Path $cache -Force
    $scriptCopy = Join-Path -Path $cache -ChildPath "$Phase.ps1"
    Copy-Item -LiteralPath $source -Destination $scriptCopy

    try {
        $processSplat = @{
            FilePath         = $hostInfo.Path
            Arguments        = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptCopy`""
            WorkingDirectory = $WorkingDirectory
            WorkFolder       = $cache
            Context          = $Context
            TimeoutSeconds   = $TimeoutSeconds
        }
        if ($Credential) {
            Grant-IslFolderAccess -Path $cache -Account $Credential.UserName
            $processSplat.Credential = $Credential
            $processSplat.LogonType = $LogonType
        }
        $run = Invoke-IslProcess @processSplat
    }
    finally {
        Remove-Item -LiteralPath $cache -Recurse -Force -ErrorAction SilentlyContinue
    }

    [pscustomobject]@{
        PSTypeName   = 'IntuneScriptLab.RunResult'
        Phase        = $Phase
        ScriptPath   = $source
        Host         = $hostInfo.Path
        Architecture = $Architecture
        Context      = $Context
        RunAs        = "$($run.UserName) ($($run.LogonType))"
        UserName     = $run.UserName
        LogonType    = $run.LogonType
        ExitCode     = $run.ExitCode
        TimedOut     = $run.TimedOut
        StdOut       = $run.StdOut
        StdErr       = $run.StdErr
        Duration     = $run.Duration
    }
}
