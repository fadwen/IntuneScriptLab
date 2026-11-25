function Invoke-IslGraphRequest {
    <#
    .SYNOPSIS
        Calls Microsoft Graph through the caller's Microsoft.Graph session.

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

    .INPUTS
        None.

    .OUTPUTS
        System.Object. Graph's reply as Invoke-MgGraphRequest returns it; with -All, each item of every page.
    #>
    [CmdletBinding()]
    [OutputType([object])]
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
        $message = ('Microsoft.Graph.Authentication is not loaded. Install-PSResource ' +
            'Microsoft.Graph.Authentication, then Connect-MgGraph -Scopes ' +
            'DeviceManagementConfiguration.Read.All, DeviceManagementApps.Read.All, ' +
            'DeviceManagementScripts.Read.All, GroupMember.Read.All')
        $recordSplat = @{
            Message = $message
            ErrorId = 'GraphModuleNotLoaded'
            Category = [System.Management.Automation.ErrorCategory]::NotInstalled
            TargetObject = 'Microsoft.Graph.Authentication'
        }
        $PSCmdlet.ThrowTerminatingError((New-IslErrorRecord @recordSplat))
    }
    $requestSplat = @{ Method = $Method; Uri = $Uri; ErrorAction = 'Stop' }
    if ($Body) { $requestSplat.Body = $Body }
    if ($Headers) { $requestSplat.Headers = $Headers }

    # The request that failed for good ends this function with Graph's own error, unchanged, so
    # that a caller reads the status code and the response from it as before
    $items = [System.Collections.Generic.List[object]]::new()
    try {
        if (-not $All) {
            $reply = Invoke-IslGraphRequestOnce -Request $requestSplat
        } else {
            $next = $Uri
            while ($next) {
                $requestSplat.Uri = $next
                $page = Invoke-IslGraphRequestOnce -Request $requestSplat
                # The last page has no next link, and an empty collection may come without a value
                $pageItems = @(Get-IslPropertyValue -InputObject $page -Name 'value')
                if ($pageItems.Count -gt 0) { $items.AddRange([object[]]$pageItems) }
                $next = Get-IslPropertyValue -InputObject $page -Name '@odata.nextLink'
            }
        }
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }

    if (-not $All) { return $reply }
    $items.ToArray()
}
