function Invoke-IntunePlatformScriptTest {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Runs a platform (device) script the way Intune does and reports its run state.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.PlatformScriptResult')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName', 'PSPath')]
        [string]$Path,

        [ValidateSet('x86', 'x64', 'arm64')]
        [string]$Architecture = 'x86',

        [ValidateSet('User', 'System')]
        [string]$Context = 'User',

        # Run as this account instead of the current user (with -Context User): a scheduled task in
        # the account's own session, the way the agent runs user-context scripts as the signed-in
        # user; needs an elevated session
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential,

        [ValidateRange(1, 86400)]
        [int]$TimeoutSeconds = 300
    )

    process {
        Write-Verbose "Starting $($MyInvocation.MyCommand.Name) for $($PSBoundParameters.Keys -join ', ')"

        $scriptRunSplat = @{
            Path           = $Path
            Architecture   = $Architecture
            Context        = $Context
            Phase          = 'script'
            TimeoutSeconds = $TimeoutSeconds
        }
        if ($Credential) {
            if ($Context -eq 'System') {
                throw '-Credential applies to -Context User; System runs as NT AUTHORITY\SYSTEM'
            }
            $scriptRunSplat.Credential = $Credential
        }
        $run = Invoke-IslScriptRun @scriptRunSplat
        $runState = if ($run.TimedOut) { 'TimedOut' } elseif ($run.ExitCode -eq 0) { 'Success' } else { 'Failed' }

        # What happens next under Intune, from the PS-FAIL experiments: a failed script is fetched and
        # run again at the agent's next script policy fetch, which happens at a service start or
        # restart and otherwise every 8 hours (the hourly Win32 check-ins fetch no script policy),
        # three runs in all, then never again
        $warnings = [System.Collections.Generic.List[string]]::new()
        if ($runState -ne 'Success') {
            $warnings.Add(('Intune runs a failed platform script again at its next script policy fetch (an ' +
                    'agent start or restart, otherwise every 8 hours), three runs in total (initial plus two ' +
                    'retries), then reports Failed for good'))
        }

        Write-Verbose "Completed $($MyInvocation.MyCommand.Name)"
        [pscustomobject]@{
            PSTypeName    = 'IntuneScriptLab.PlatformScriptResult'
            RunState      = $runState
            ExitCode      = $run.ExitCode
            ResultMessage = ($run.StdOut + $run.StdErr).TrimEnd("`r", "`n")
            StdOut        = $run.StdOut
            StdErr        = $run.StdErr
            TimedOut      = $run.TimedOut
            Duration      = $run.Duration
            Warnings      = $warnings.ToArray()
            Architecture  = $Architecture
            Context       = $Context
            RunAs         = $run.RunAs
            Host          = $run.Host
            ScriptPath    = $run.ScriptPath
        }
    }
}
