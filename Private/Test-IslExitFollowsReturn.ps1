function Test-IslExitFollowsReturn {
    <#
    .SYNOPSIS
    Tells whether an exit with a code other than 0 follows a return in the same block.

    .DESCRIPTION
    For the exit-code rule. Such an exit is the one the author meant. Writing exit 0 in front of
    it would leave it unreachable with no finding left to say so, so a return that it follows gets
    no edit and stays reported.

    .PARAMETER Return
    The return statement.

    .EXAMPLE
    Test-IslExitFollowsReturn -Return $return

    $true for the return in: return 'missing'; exit 1.

    .INPUTS
    None.

    .OUTPUTS
    System.Boolean.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.ReturnStatementAst]$Return
    )

    $passed = $false
    foreach ($statement in @($Return.Parent.Statements)) {
        if ($statement -eq $Return) { $passed = $true; continue }
        if (-not $passed -or $statement.GetType().Name -ne 'ExitStatementAst') { continue }
        if ($statement.Pipeline -and $statement.Pipeline.Extent.Text.Trim() -ne '0') { return $true }
    }
    $false
}
