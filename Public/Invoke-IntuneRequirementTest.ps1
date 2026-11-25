function Invoke-IntuneRequirementTest {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Runs a Win32 requirement script like Intune and applies the rule to its output.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('IntuneScriptLab.RequirementResult')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName', 'PSPath')]
        [string[]]$Path,

        [Parameter(Mandatory)]
        [ValidateSet('String', 'DateTime', 'Integer', 'Float', 'Version', 'Boolean')]
        [string]$OutputType,

        [ValidateSet('Equal', 'NotEqual', 'GreaterThan', 'GreaterThanOrEqual', 'LessThan', 'LessThanOrEqual')]
        [string]$Operator = 'Equal',

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value,

        # Left out: the device's 64-bit host (x64, or arm64 on Windows on ARM), the agent's default
        [ValidateSet('x86', 'x64', 'arm64')]
        [string]$Architecture,

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

    begin {
        if ($Credential -and $Context -eq 'System') {
            $recordSplat = @{
                Message = '-Credential applies to -Context User; System runs as NT AUTHORITY\SYSTEM'
                ErrorId = 'CredentialWithSystemContext'
                Category = [System.Management.Automation.ErrorCategory]::InvalidArgument
                TargetObject = $Context
                ExceptionType = [System.ArgumentException]
            }
            $PSCmdlet.ThrowTerminatingError((New-IslErrorRecord @recordSplat))
        }
        Write-Verbose "Starting $($MyInvocation.MyCommand.Name)"
        # The agent's default host is the device's 64-bit one: arm64 on Windows on ARM, where no x64
        # host exists, and x64 elsewhere
        $runArchitecture = $Architecture
        if (-not $runArchitecture) { $runArchitecture = Get-IslHostArchitecture }
    }

    process {
        foreach ($scriptItem in $Path) {
            # Path is bound only here when it comes from the pipeline, so each script is named here
            Write-Verbose "Testing $scriptItem"
            $scriptRunSplat = @{
                Path           = $scriptItem
                Architecture   = $runArchitecture
                Context        = $Context
                Phase          = 'requirement'
                TimeoutSeconds = $TimeoutSeconds
            }
            if ($Credential) { $scriptRunSplat.Credential = $Credential }
            # The script is somebody's code and is about to run: -WhatIf names it and runs nothing
            $action = "Run as a Win32 requirement script ($Context context, $runArchitecture)"
            if (-not $PSCmdlet.ShouldProcess($scriptItem, $action)) {
                continue
            }

            # A script that cannot be run is reported, and the next one still runs
            try {
                $run = Invoke-IslScriptRun @scriptRunSplat
            } catch {
                # Once for each script, also for a failure that every script shares, such as a host
                # this device does not have: the unit tests mock the launch with architectures the
                # test computer may not have
                $PSCmdlet.WriteError($_)
                continue
            }

            $compareSplat = @{
                StdOut     = $run.StdOut
                StdErr     = $run.StdErr
                ExitCode   = $run.ExitCode
                TimedOut   = $run.TimedOut
                OutputType = $OutputType
                Operator   = $Operator
                Value      = $Value
            }
            $verdict = Compare-IslRequirementOutput @compareSplat

            [pscustomobject]@{
                PSTypeName   = 'IntuneScriptLab.RequirementResult'
                Applicable   = $verdict.Met
                Reason       = $verdict.Reason
                Output       = $verdict.Output
                ExitCode     = $run.ExitCode
                StdOut       = $run.StdOut
                StdErr       = $run.StdErr
                TimedOut     = $run.TimedOut
                Duration     = $run.Duration
                OutputType   = $OutputType
                Operator     = $Operator
                Value        = $Value
                Architecture = $runArchitecture
                Context      = $Context
                RunAs        = $run.RunAs
                Host         = $run.Host
                ScriptPath   = $run.ScriptPath
            }
        }
    }

    end {
        Write-Verbose "Completed $($MyInvocation.MyCommand.Name)"
    }
}
