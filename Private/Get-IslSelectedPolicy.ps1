function Get-IslSelectedPolicy {
    <#
    .SYNOPSIS
    Gets the policies of one Graph list that the caller's -Name and -Id select.

    .DESCRIPTION
    For the tenant commands Test-IntuneDeployedScript, Compare-IntuneDeployedScript and
    Get-IntuneScriptHealth. Reads every page of the list through Invoke-IslGraphRequest and keeps
    the policies that Test-IslPolicySelected selects. A list that cannot be read ends the
    function with Graph's own error, so the caller can read its status code.

    .PARAMETER Uri
    The Graph list to read, such as /beta/deviceManagement/deviceHealthScripts?$select=id,displayName.

    .PARAMETER Name
    The wildcard patterns of the caller's -Name.

    .PARAMETER Id
    The ids of the caller's -Id. Nothing when the caller gave none.

    .PARAMETER NameGiven
    Whether the caller gave -Name itself, rather than taking its default.

    .EXAMPLE
    Get-IslSelectedPolicy -Uri '/beta/deviceManagement/deviceManagementScripts' -Id $scriptId

    The platform script with that id, as the list returns it.

    .INPUTS
    None.

    .OUTPUTS
    System.Object. Each selected policy as Graph returns it.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$Name = @('*'),

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$Id,

        [Parameter()]
        [switch]$NameGiven
    )

    $selection = @{ Name = $Name; Id = $Id; NameGiven = $NameGiven }
    try {
        $policies = @(Invoke-IslGraphRequest -Uri $Uri -All -ErrorAction Stop)
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
    foreach ($policy in $policies) {
        if (Test-IslPolicySelected -Policy $policy @selection) { $policy }
    }
}
