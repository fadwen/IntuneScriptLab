function Invoke-IntuneDetectionTest {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Runs a Win32 custom detection script like Intune and returns the verdict.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('IntuneScriptLab.DetectionResult')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName', 'PSPath')]
        [string[]]$Path,

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
        [int]$TimeoutSeconds = 300,

        [switch]$EnforceSignatureCheck
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
            # The script is somebody's code and is about to run: -WhatIf names it and runs nothing
            $action = "Run as a Win32 detection script ($Context context, $runArchitecture)"
            if (-not $PSCmdlet.ShouldProcess($scriptItem, $action)) {
                continue
            }

            $reasons = [System.Collections.Generic.List[string]]::new()
            $signatureStatus = ''
            $run = $null
            $scriptPath = $null
            # A script that cannot be run is reported, and the next one still runs
            try {
                if ($EnforceSignatureCheck) {
                    $scriptPath = (Resolve-Path -LiteralPath $scriptItem -ErrorAction Stop).ProviderPath
                    # With the check on, AgentExecutor returns exit 1 for an unsigned script without
                    # running it: no probe record, "EnforceSignatureCheck: 1 ... applicationDetected:
                    # False" (W32-DET-SIGCHECK)
                    $signature = Get-AuthenticodeSignature -FilePath $scriptPath -ErrorAction Stop
                    $signatureStatus = "$($signature.Status)"
                    if ($signature.Status -ne 'Valid') {
                        $reasons.Add("Signature status ${signatureStatus}: with the signature check enforced " +
                            'the agent does not run the script and reports not detected (exit 1 from ' +
                            'AgentExecutor)')
                    }
                }

                if ($reasons.Count -eq 0) {
                    $scriptRunSplat = @{
                        Path = $scriptItem
                        Architecture = $runArchitecture
                        Context = $Context
                        Phase = 'detect'
                        TimeoutSeconds = $TimeoutSeconds
                    }
                    if ($Credential) { $scriptRunSplat.Credential = $Credential }
                    $run = Invoke-IslScriptRun @scriptRunSplat
                }
            } catch {
                # Once for each script, also for a failure that every script shares, such as a host
                # this device does not have: the unit tests mock the launch with architectures the
                # test computer may not have
                $PSCmdlet.WriteError($_)
                continue
            }

            if ($null -ne $run) {
                $hasStdOut = -not [string]::IsNullOrWhiteSpace($run.StdOut)
                $hasStdErr = -not [string]::IsNullOrWhiteSpace($run.StdErr)

                if ($run.TimedOut) {
                    $reasons.Add("Timed out after $TimeoutSeconds s; Intune kills the script at its " +
                        '60-minute timeout and reports not detected')
                } elseif ($run.ExitCode -ne 0) {
                    $reasons.Add("Exit code $($run.ExitCode): only exit 0 can mean installed")
                }
                if (-not $hasStdOut) { $reasons.Add('Nothing on stdout: exit 0 alone is "not detected"') }
                if ($hasStdErr) {
                    $reasons.Add('Output on stderr: any error output means "not detected" even with exit 0 ' +
                        'and stdout')
                }
            }

            [pscustomobject]@{
                PSTypeName = 'IntuneScriptLab.DetectionResult'
                Detected = ($reasons.Count -eq 0)
                Reason = if ($reasons.Count -eq 0) {
                    ('Exit 0 with stdout and no ' +
                    'stderr')
                } else { $reasons -join '; ' }
                ExitCode = if ($run) { $run.ExitCode } else { 1 }
                StdOut = if ($run) { $run.StdOut } else { '' }
                StdErr = if ($run) { $run.StdErr } else { '' }
                TimedOut = if ($run) { $run.TimedOut } else { $false }
                Duration = if ($run) { $run.Duration } else { [timespan]::Zero }
                SignatureStatus = $signatureStatus
                Architecture = $runArchitecture
                Context = $Context
                RunAs = if ($run) { $run.RunAs } else { '' }
                Host = if ($run) { $run.Host } else { '' }
                ScriptPath = if ($run) { $run.ScriptPath } else { $scriptPath }
            }
        }
    }

    end {
        Write-Verbose "Completed $($MyInvocation.MyCommand.Name)"
    }
}
