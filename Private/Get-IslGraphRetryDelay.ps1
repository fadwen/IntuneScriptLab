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
    of another type with the same members serves in the tests. A response without a Retry-After
    header, or of a type that has no RetryAfter member, such as the HttpWebResponse of a
    WebException, gets the doubling delay.

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
    $exceptionStatus = Get-IslPropertyValue -InputObject $exception -Name 'StatusCode'
    if ($exceptionStatus) { $status = [int]$exceptionStatus }
    $response = Get-IslPropertyValue -InputObject $exception -Name 'Response'
    if (-not $status -and $response) {
        $responseStatus = Get-IslPropertyValue -InputObject $response -Name 'StatusCode'
        if ($responseStatus) { $status = [int]$responseStatus }
    }
    if ($status -notin 429, 503, 504) { return }

    $delay = 0
    # Headers.RetryAfter is a member of HttpResponseMessage only. The response of another type,
    # such as the HttpWebResponse of a WebException, has no such member and gets the doubling
    # delay. The headers are a collection, which a function would unroll into its entries, so
    # they are read here and not through Get-IslPropertyValue
    $retryAfter = $null
    $headersProperty = $null
    if ($null -ne $response) { $headersProperty = $response.PSObject.Properties['Headers'] }
    if ($null -ne $headersProperty -and $null -ne $headersProperty.Value) {
        $retryProperty = $headersProperty.Value.PSObject.Properties['RetryAfter']
        if ($null -ne $retryProperty) { $retryAfter = $retryProperty.Value }
    }
    if ($retryAfter) {
        $retryDelta = Get-IslPropertyValue -InputObject $retryAfter -Name 'Delta'
        $retryDate = Get-IslPropertyValue -InputObject $retryAfter -Name 'Date'
        if ($null -ne $retryDelta) {
            $delay = [Math]::Ceiling($retryDelta.TotalSeconds)
        } elseif ($null -ne $retryDate) {
            $delay = [Math]::Ceiling(($retryDate.UtcDateTime - [datetime]::UtcNow).TotalSeconds)
        }
    }
    if ($delay -lt 1) { $delay = [Math]::Pow(2, $Attempt) }
    [int][Math]::Min($delay, 60)
}
