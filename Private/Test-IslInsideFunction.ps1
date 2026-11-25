function Test-IslInsideFunction {
    <#
    .SYNOPSIS
        Tells whether a syntax tree node is inside a function or nested script block.

    .DESCRIPTION
        For the analyzer's rules about return and exit, which there do not necessarily end the
        script. A node counts as inside when any of its parents is a function definition or a
        script block expression, such as the block passed to ForEach-Object. The script's own
        root body does not count.

    .PARAMETER Node
        The node to test.

    .EXAMPLE
        Test-IslInsideFunction -Node $exitStatement

        $true for the exit in 1..2 | ForEach-Object { exit 2 }, $false for an exit at script level.

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
    $parent = $Node.Parent
    while ($parent) {
        if ($parent.GetType().Name -eq 'FunctionDefinitionAst') { return $true }
        # A script block that isn't the script's own root body (e.g. a ForEach-Object block)
        if ($parent.GetType().Name -eq 'ScriptBlockExpressionAst') { return $true }
        $parent = $parent.Parent
    }
    $false
}
