function Get-IslGraphRetryDelay {
    <#
    .SYNOPSIS
    Gets how long to wait before sending a failed Graph request again.

    .DESCRIPTION
    Microsoft Graph asks a client to come back later with 429 (too many requests), 503 and 504.
    For those, the delay is the one the reply's Retry-After header gives, as a number of seconds
    or as a date, and otherwise 2 to the power of the attempt; it is at most 60 seconds. For any
    other failure there is nothing to wait for, and the function returns nothing. The status code
    and the response are read from Invoke-MgGraphRequest's exception by name, so an exception
    of another type with the same members serves in the tests.

    .PARAMETER ErrorRecord
    The error of the request that failed.

    .PARAMETER Attempt
    The number of the attempt that failed, from 1.

    .EXAMPLE
    $delay = Get-IslGraphRetryDelay -ErrorRecord $_ -Attempt 1

    In a catch: 2 for a 503 without Retry-After, nothing for a 404.

    .INPUTS
    None.

    .OUTPUTS
    System.Int32. The delay in seconds, or nothing when the request is not to be sent again.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        [Parameter(Mandatory)]
        [ValidateRange(1, 100)]
        [int]$Attempt
    )

    $exception = $ErrorRecord.Exception
    $status = 0
    if ($exception.PSObject.Properties['StatusCode'] -and $exception.StatusCode) {
        $status = [int]$exception.StatusCode
    }
    $response = if ($exception.PSObject.Properties['Response']) { $exception.Response } else { $null }
    if (-not $status -and $response) { $status = [int]$response.StatusCode }
    if ($status -notin 429, 503, 504) { return }

    $delay = 0
    $retryAfter = if ($response) { $response.Headers.RetryAfter } else { $null }
    if ($retryAfter) {
        if ($null -ne $retryAfter.Delta) { $delay = [Math]::Ceiling($retryAfter.Delta.TotalSeconds) }
        elseif ($null -ne $retryAfter.Date) {
            $delay = [Math]::Ceiling(($retryAfter.Date.UtcDateTime - [datetime]::UtcNow).TotalSeconds)
        }
    }
    if ($delay -lt 1) { $delay = [Math]::Pow(2, $Attempt) }
    [int][Math]::Min($delay, 60)
}
