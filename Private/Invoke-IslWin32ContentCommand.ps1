function Invoke-IslWin32ContentCommand {
    <#
    .SYNOPSIS
    Runs a Win32 app's install or uninstall command line from a copy of its content folder.

    .DESCRIPTION
    For Invoke-IntuneWin32AppTest. The content is copied to a run folder, the command line runs
    there through the 32-bit cmd.exe, as the agent's own 32-bit process runs it, and the run
    folder is removed afterwards. A run as another account gets its folder under ProgramData,
    which that account can reach, with Modify access granted to it.

    A command line that starts powershell.exe, or that names a batch file in the content which
    does, runs the 32-bit host, where HKLM:\SOFTWARE and Program Files are redirected; that adds
    a warning to the list it is given.

    A copy or a launch that fails ends the function with its error.

    .PARAMETER Phase
    install or uninstall, for the result and the warnings.

    .PARAMETER Content
    The content folder of the app.

    .PARAMETER CommandLine
    The install or uninstall command line, as the app defines it.

    .PARAMETER Context
    User or System.

    .PARAMETER Credential
    The account to run as, with Context User. Left out, the run is the current user's.

    .PARAMETER TimeoutSeconds
    How long the command line may run before it is ended.

    .PARAMETER Warning
    The list the warnings of the run are collected in.

    .EXAMPLE
    $contentSplat = @{ Context = 'User'; TimeoutSeconds = 600; Warning = $warnings }
    Invoke-IslWin32ContentCommand -Phase 'install' -Content $ContentPath -CommandLine 'setup.exe /q' @contentSplat

    Runs the install command line as the current user.

    .INPUTS
    None.

    .OUTPUTS
    IntuneScriptLab.RunResult. Phase, Command, Context, ExitCode, TimedOut, StdOut, StdErr and
    Duration.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.RunResult')]
    param(
        [Parameter(Mandatory)]
        [string]$Phase,

        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [string]$CommandLine,

        [Parameter(Mandatory)]
        [ValidateSet('User', 'System')]
        [string]$Context,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]::Empty,

        [Parameter(Mandatory)]
        [ValidateRange(1, 86400)]
        [int]$TimeoutSeconds,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Warning
    )

    $asAccount = $Credential -ne [System.Management.Automation.PSCredential]::Empty
    try {
        $source = (Resolve-Path -LiteralPath $Content -ErrorAction Stop).ProviderPath
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
    $hostPattern = '(?i)(^|[\s"])powershell(\.exe)?([\s"]|$)'
    if ($CommandLine -match $hostPattern) {
        $Warning.Add("powershell.exe in the $Phase command runs the 32-bit host (the agent is a 32-bit " +
            'process); HKLM:\SOFTWARE and Program Files are redirected there')
    } else {
        # The same host hides inside a batch file the command line names: install.cmd calling
        # powershell.exe runs it 32-bit too, from the agent's 32-bit cmd.exe, without the
        # command line showing it
        $first = if ($CommandLine -match '^\s*"([^"]+)"') {
            $Matches[1]
        } else {
            ($CommandLine.Trim() -split '\s+', 2)[0]
        }
        $batch = if ($first -match '(?i)\.(cmd|bat)$') {
            Join-Path -Path $source -ChildPath $first
        } else {
            $null
        }
        if ($batch -and (Test-Path -LiteralPath $batch -PathType Leaf)) {
            $hit = Select-String -LiteralPath $batch -Pattern $hostPattern | Select-Object -First 1
            if ($hit) {
                $Warning.Add("powershell.exe in $first (line $($hit.LineNumber)), which the $Phase " +
                    'command runs through the 32-bit cmd.exe, is the 32-bit host (the agent is a 32-bit ' +
                    'process); HKLM:\SOFTWARE and Program Files are redirected there')
            }
        }
    }
    $runId = [guid]::NewGuid().ToString('N')
    # Another account cannot reach the caller's temp folder; its copy lives under ProgramData
    $cache = if ($asAccount) {
        Join-Path -Path $env:ProgramData -ChildPath "IntuneScriptLab\Runs\$runId"
    } else {
        Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "IntuneScriptLab\$runId"
    }
    $copy = Join-Path -Path $cache -ChildPath 'content'
    try {
        $null = New-Item -ItemType Directory -Path $copy -Force -ErrorAction Stop @script:IslInternal
        $contentItems = Join-Path -Path $source -ChildPath '*'
        $copySplat = @{ Path = $contentItems; Destination = $copy; Recurse = $true; Force = $true }
        Copy-Item @copySplat -ErrorAction Stop @script:IslInternal
        if ($asAccount) { Grant-IslFolderAccess -Path $cache -Account $Credential.UserName }
        $cmdFolder = if ([Environment]::Is64BitOperatingSystem) { 'SysWOW64' } else { 'System32' }
        $cmd = Join-Path -Path (Join-Path -Path $env:WINDIR -ChildPath $cmdFolder) -ChildPath 'cmd.exe'
        $processSplat = @{
            FilePath = $cmd
            Arguments = "/C `"$CommandLine`""
            WorkingDirectory = $copy
            WorkFolder = $cache
            Context = $Context
            TimeoutSeconds = $TimeoutSeconds
            LauncherBitness = 'x86'
        }
        if ($asAccount) { $processSplat.Credential = $Credential }
        $run = Invoke-IslProcess @processSplat
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    } finally {
        Remove-Item -LiteralPath $cache -Recurse -Force -ErrorAction SilentlyContinue @script:IslInternal
    }

    [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.RunResult'
        Phase = $Phase
        Command = $CommandLine
        Context = $Context
        ExitCode = $run.ExitCode
        TimedOut = $run.TimedOut
        StdOut = $run.StdOut
        StdErr = $run.StdErr
        Duration = $run.Duration
    }
}
