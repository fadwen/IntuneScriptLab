function Test-IslInsideTryWithCatch {
    <#
    .SYNOPSIS
        True when the node is inside the body of a try that has a catch block.
    #>
    [CmdletBinding()]
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
