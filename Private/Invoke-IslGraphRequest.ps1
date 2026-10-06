function Invoke-IslGraphRequest {
    <#
    .SYNOPSIS
        Calls Microsoft Graph through the caller's Microsoft.Graph.Authentication session.

    .DESCRIPTION
        A thin wrapper over Invoke-MgGraphRequest: one place that checks the Graph module is loaded
        and connected, follows @odata.nextLink when -All is given, retries a throttled or
        unavailable answer, and is the single seam the unit tests mock. The module does not depend
        on Microsoft.Graph.Authentication; the caller installs it and runs Connect-MgGraph with
        DeviceManagementConfiguration.Read.All, DeviceManagementApps.Read.All and
        DeviceManagementScripts.Read.All (plus GroupMember.Read.All when assignments are inspected)
        before Test-IntuneDeployedScript is used.

        Graph answers 429 when a client is throttled and 503 or 504 when a service is briefly
        unavailable, with a Retry-After header on the first. A request that gets one of those is
        sent again up to three times, after the Retry-After seconds when the header is there and
        after 2, 4 and 8 seconds when it is not; the fourth failure is thrown as it came. A tenant
        command makes two requests per policy, so a pre-flight over a few hundred policies meets
        the throttle without this.

    .PARAMETER Uri
        The request URI, absolute or relative to the Graph root, e.g.
        /beta/deviceManagement/deviceHealthScripts.

    .PARAMETER Method
        GET (default) or POST.

    .PARAMETER Body
        The request body for a POST.

    .PARAMETER Headers
        Request headers, e.g. @{ ConsistencyLevel = 'eventual' } for a $count query.

    .PARAMETER All
        Follow @odata.nextLink and return every item of the collection instead of the first page.

    .EXAMPLE
        Invoke-IslGraphRequest -Uri '/beta/deviceManagement/deviceHealthScripts?$select=id,displayName' -All

        Every remediation in the tenant, id and name only.

    .EXAMPLE
        $countSplat = @{ Headers = @{ ConsistencyLevel = 'eventual' } }
        Invoke-IslGraphRequest -Uri '/v1.0/groups/{id}/members/microsoft.graph.device/$count' @countSplat

        The number of devices among the group's members, as text.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [ValidateSet('GET', 'POST')]
        [string]$Method = 'GET',

        [hashtable]$Body,

        [hashtable]$Headers,

        [switch]$All
    )

    if (-not (Get-Command -Name Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) {
        throw ('Microsoft.Graph.Authentication is not loaded. Install-PSResource ' +
            'Microsoft.Graph.Authentication, then Connect-MgGraph -Scopes ' +
            'DeviceManagementConfiguration.Read.All, DeviceManagementApps.Read.All, ' +
            'DeviceManagementScripts.Read.All, GroupMember.Read.All')
    }
    $requestSplat = @{ Method = $Method; Uri = $Uri; ErrorAction = 'Stop' }
    if ($Body) { $requestSplat.Body = $Body }
    if ($Headers) { $requestSplat.Headers = $Headers }

    # How long to wait before sending a failed request again, or nothing when the failure is not
    # one that passes. Invoke-MgGraphRequest's exception carries the status code and the response;
    # both are read by name so a stand-in exception with the same members serves in the tests
    function Get-RetryDelay {
        param($ErrorRecord, [int]$Attempt)
        $exception = $ErrorRecord.Exception
        $status = 0
        if ($exception.PSObject.Properties['StatusCode'] -and $exception.StatusCode) {
            $status = [int]$exception.StatusCode
        }
        $response = if ($exception.PSObject.Properties['Response']) { $exception.Response } else { $null }
        if (-not $status -and $response) { $status = [int]$response.StatusCode }
        if ($status -notin 429, 503, 504) { return $null }

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

    function Invoke-Once {
        param([hashtable]$Splat)
        $attempt = 0
        while ($true) {
            try {
                return Invoke-MgGraphRequest @Splat
            }
            catch {
                $attempt++
                $delay = if ($attempt -le 3) { Get-RetryDelay -ErrorRecord $_ -Attempt $attempt } else { $null }
                if ($null -eq $delay) { throw }
                Write-Verbose ("Graph answered $($_.Exception.Message); retry $attempt of 3 in $delay s: " +
                    $Splat.Uri)
                Start-Sleep -Seconds $delay
            }
        }
    }

    if (-not $All) { return Invoke-Once -Splat $requestSplat }

    $items = [System.Collections.Generic.List[object]]::new()
    $next = $Uri
    while ($next) {
        $requestSplat.Uri = $next
        $page = Invoke-Once -Splat $requestSplat
        if ($page.value) { $items.AddRange([object[]]$page.value) }
        $next = $page.'@odata.nextLink'
    }
    $items.ToArray()
}
