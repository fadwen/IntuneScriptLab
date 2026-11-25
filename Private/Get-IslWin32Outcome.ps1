function Get-IslWin32Outcome {
    <#
    .SYNOPSIS
    Gets what the agent makes of the exit code of a Win32 app's install or uninstall.

    .DESCRIPTION
    For Invoke-IntuneWin32AppTest. A run that was ended at its timeout is timedOut. Otherwise the
    exit code is looked up in the app's return codes, such as 0 = success, 3010 = softReboot or
    1618 = retry, and a code that is not there is failed.

    .PARAMETER Run
    The run, with TimedOut and ExitCode.

    .PARAMETER ReturnCodes
    The app's return codes: exit code to success, softReboot, hardReboot, retry or failed.

    .EXAMPLE
    Get-IslWin32Outcome -Run $execution -ReturnCodes @{ 0 = 'success'; 3010 = 'softReboot' }

    softReboot for a run that exited 3010.

    .INPUTS
    None.

    .OUTPUTS
    System.String. timedOut, failed, or the value of the exit code in the return codes.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject]$Run,

        [Parameter(Mandatory)]
        [hashtable]$ReturnCodes
    )

    if ($Run.TimedOut) {
        return 'timedOut'
    }
    if ($null -ne $Run.ExitCode -and $ReturnCodes.ContainsKey($Run.ExitCode)) {
        return "$($ReturnCodes[$Run.ExitCode])"
    }
    'failed'
}
