function Test-IslInsideTryWithCatch {
    <#
    .SYNOPSIS
        Tells whether a node of a syntax tree is in the body of a try that has a catch.

    .DESCRIPTION
        For the analyzer's rules about errors that end a script. A node in a catch or finally
        block does not count, nor does one in a try that has only a finally.

    .PARAMETER Node
        The node to test.

    .EXAMPLE
        Test-IslInsideTryWithCatch -Node $command

        $true for the Get-Item in try { Get-Item C:\a -ErrorAction Stop } catch { exit 1 }.

    .INPUTS
        None.

    .OUTPUTS
        System.Boolean.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Node
    )
    $child = $Node
    $parent = $Node.Parent
    while ($parent) {
        $isTry = $parent.GetType().Name -eq 'TryStatementAst'
        if ($isTry -and $parent.Body -eq $child -and $parent.CatchClauses.Count -gt 0) {
            return $true
        }
        $child = $parent
        $parent = $parent.Parent
    }
    $false
}
