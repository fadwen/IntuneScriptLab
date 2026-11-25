function Get-IslRunSummary {
    <#
    .SYNOPSIS
    Gets the run summary of a remediation or platform script, or nothing when it cannot be read.

    .DESCRIPTION
    For Get-IntuneScriptHealth. Reads the runSummary of one policy through Invoke-IslGraphRequest.
    A summary that cannot be read is not a reason to stop the report: it writes a warning that
    names the address and the error, and returns nothing, so the policy's device columns stay
    empty.

    .PARAMETER Uri
    The runSummary address, such as /beta/deviceManagement/deviceHealthScripts/<id>/runSummary.

    .EXAMPLE
    Get-IslRunSummary -Uri "/beta/deviceManagement/deviceManagementScripts/$scriptId/runSummary"

    The script's run summary with its successDeviceCount and errorDeviceCount.

    .INPUTS
    None.

    .OUTPUTS
    System.Object. The summary as Graph returns it, or nothing.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [string]$Uri
    )

    $summary = $null
    try {
        $summary = Invoke-IslGraphRequest -Uri $Uri -ErrorAction Stop
    } catch {
        # A run summary only fills in the device columns; the report goes on without them
        Write-Warning "Run summary could not be read from $Uri ($($_.Exception.Message))"
    }
    if ($null -ne $summary) { $summary }
}
