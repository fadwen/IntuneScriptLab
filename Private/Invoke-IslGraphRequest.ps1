function Invoke-IslGraphRequest {
    <#
    .SYNOPSIS
        Calls Microsoft Graph through the caller's Microsoft.Graph.Authentication session.

    .DESCRIPTION
        A thin wrapper over Invoke-MgGraphRequest: one place that checks the Graph module is loaded
        and connected, follows @odata.nextLink when -All is given, and is the single seam the unit
        tests mock. The module does not depend on Microsoft.Graph.Authentication; the caller
        installs it and runs Connect-MgGraph with DeviceManagementConfiguration.Read.All,
        DeviceManagementApps.Read.All and DeviceManagementScripts.Read.All (plus GroupMember.Read.All
        when assignments are inspected) before Test-IntuneDeployedScript is used.

    .PARAMETER Uri
        The request URI, absolute or relative to the Graph root, e.g.
        /beta/deviceManagement/deviceHealthScripts.

    .PARAMETER Method
        GET (default) or POST.

    .PARAMETER Body
        The request body for a POST.

    .PARAMETER All
        Follow @odata.nextLink and return every item of the collection instead of the first page.

    .EXAMPLE
        Invoke-IslGraphRequest -Uri '/beta/deviceManagement/deviceHealthScripts?$select=id,displayName' -All

        Every remediation in the tenant, id and name only.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [ValidateSet('GET', 'POST')]
        [string]$Method = 'GET',

        [hashtable]$Body,

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

    if (-not $All) { return Invoke-MgGraphRequest @requestSplat }

    $items = [System.Collections.Generic.List[object]]::new()
    $next = $Uri
    while ($next) {
        $requestSplat.Uri = $next
        $page = Invoke-MgGraphRequest @requestSplat
        if ($page.value) { $items.AddRange([object[]]$page.value) }
        $next = $page.'@odata.nextLink'
    }
    $items.ToArray()
}
