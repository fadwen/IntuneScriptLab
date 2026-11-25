function Invoke-IslGraphRequestOnce {
    <#
    .SYNOPSIS
    Sends one Graph request, again up to three times when Graph asks for that.

    .DESCRIPTION
    One page of Invoke-IslGraphRequest. A reply of 429, 503 or 504 is followed by a wait of the
    delay Get-IslGraphRetryDelay gives and another attempt, three at most. Any other failure, and
    the fourth failure of one that passes, ends the function with Graph's own error, unchanged,
    so that the caller reads the status code and the response from it.

    .PARAMETER Request
    The parameters of Invoke-MgGraphRequest: Method and Uri, and Body and Headers when the
    request has them. ErrorAction Stop is expected among them.

    .EXAMPLE
    $page = Invoke-IslGraphRequestOnce -Request @{ Method = 'GET'; Uri = '/v1.0/me'; ErrorAction = 'Stop' }

    The reply to one GET.

    .INPUTS
    None.

    .OUTPUTS
    System.Object. The reply of Invoke-MgGraphRequest, as it returns it.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Request
    )

    $attempt = 0
    while ($true) {
        try {
            $reply = Invoke-MgGraphRequest @Request
            break
        } catch {
            $attempt++
            $delay = $null
            if ($attempt -le 3) {
                $delay = Get-IslGraphRetryDelay -ErrorRecord $_ -Attempt $attempt
            }
            if ($null -eq $delay) {
                $PSCmdlet.ThrowTerminatingError($_)
            }
            Write-Verbose ("Graph answered $($_.Exception.Message); retry $attempt of 3 in $delay s: " +
                $Request['Uri'])
            Start-Sleep -Seconds $delay
        }
    }
    $reply
}
