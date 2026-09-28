function Invoke-IntuneRemediationTest {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Runs a detection/remediation pair like Intune and reports the portal status.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.RemediationResult')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$DetectionPath,

        [Parameter(Position = 1)]
        [string]$RemediationPath,

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
    Write-Verbose "Starting $($MyInvocation.MyCommand.Name) for $($PSBoundParameters.Keys -join ', ')"

    $warnings = [System.Collections.Generic.List[string]]::new()
    $scriptRunSplat = @{
        Architecture   = $Architecture
        Context        = $Context
        TimeoutSeconds = $TimeoutSeconds
    }
    if ($Credential) {
        if ($Context -eq 'System') {
            throw '-Credential applies to -Context User; System runs as NT AUTHORITY\SYSTEM'
        }
        $scriptRunSplat.Credential = $Credential
    }
    $pre = Invoke-IslScriptRun -Path $DetectionPath -Phase 'detect' @scriptRunSplat
    $remediation = $null
    $post = $null

    if ($pre.TimedOut) {
        $status = 'TimedOut'
    }
    elseif ($pre.ExitCode -eq 0) {
        $status = 'Without issues'
    }
    else {
        if ($pre.ExitCode -ne 1) {
            $warnings.Add("Detection exited $($pre.ExitCode): Intune treats any non-zero exit as 'issue found' " +
                "(observed with 2 and -1); use 1 to be explicit")
        }
        if (-not $RemediationPath) {
            $status = 'Issue detected (no remediation script)'
        }
        else {
            $remediation = Invoke-IslScriptRun -Path $RemediationPath -Phase 'remediate' @scriptRunSplat
            if ($remediation.TimedOut) { $status = 'TimedOut' }
            elseif ($remediation.ExitCode -ne 0) { $status = 'Failed' }
            else {
                $post = Invoke-IslScriptRun -Path $DetectionPath -Phase 'detect' @scriptRunSplat
                $status = if ($post.TimedOut) { 'TimedOut' }
                elseif ($post.ExitCode -eq 0) { 'Fixed' }
                else { 'Recurred' }
            }
        }
    }

    $intune = Get-IslIntuneOutput -StdOut $pre.StdOut -StdErr $pre.StdErr
    if ($intune.DroppedLines -gt 0) { $warnings.Add("Detection wrote $($intune.DroppedLines + 1) lines; Intune " +
        "reports only the last one") }
    if ($intune.OutputTruncated) { $warnings.Add('Detection output exceeds 2,048 characters; Intune keeps the ' +
        'last 2,048') }
    if ($intune.ErrorTruncated) { $warnings.Add('Detection error output exceeds 2,048 characters; Intune keeps ' +
        'the last 2,048') }
    if ($pre.StdOut -match '[^\x00-\x7F]') { $warnings.Add('Non-ASCII in output: Intune reports it through the ' +
        'OEM code page (see IntuneOutput for the effect)') }
    if ($status -eq 'Without issues' -and $pre.StdErr) { $warnings.Add('Detection wrote to stderr but exited 0; ' +
        'Intune shows the error text but still reports "without issues"') }

    $postIntune = if ($post) { Get-IslIntuneOutput -StdOut $post.StdOut -StdErr $post.StdErr } else { $null }
    $remIntune = if ($remediation) {
        Get-IslIntuneOutput -StdOut $remediation.StdOut -StdErr $remediation.StdErr
    }
    else { $null }

    Write-Verbose "Completed $($MyInvocation.MyCommand.Name)"
    [pscustomobject]@{
        PSTypeName         = 'IntuneScriptLab.RemediationResult'
        Status             = $status
        IntuneOutput       = $intune.Output
        IntuneError        = $intune.Error
        RemediationOutput  = if ($remIntune) { $remIntune.Output } else { $null }
        PostOutput         = if ($postIntune) { $postIntune.Output } else { $null }
        PreDetection       = $pre
        Remediation        = $remediation
        PostDetection      = $post
        Warnings           = $warnings.ToArray()
        Architecture       = $Architecture
        Context            = $Context
        RunAs              = $pre.RunAs
        Host               = $pre.Host
    }
}
