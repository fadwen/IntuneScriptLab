function Get-IslReturnReplacement {
    <#
    .SYNOPSIS
    Gets the edit that says what a return at script scope already does.

    .DESCRIPTION
    For the exit-code rule. A return at script scope ends the script with exit code 0, after it
    has written the value it returned. The edit writes that out: the value followed by exit 0, or
    exit 0 alone for a bare return.

    .PARAMETER Return
    The return statement.

    .EXAMPLE
    Get-IslReturnReplacement -Return $return

    '1; exit 0' for return 1.

    .INPUTS
    None.

    .OUTPUTS
    System.String.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.ReturnStatementAst]$Return
    )

    if ($Return.Pipeline) { "$($Return.Pipeline.Extent.Text); exit 0" } else { 'exit 0' }
}
