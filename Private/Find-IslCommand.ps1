function Find-IslCommand {
    <#
    .SYNOPSIS
        Finds the invocations of the named commands in a syntax tree.

    .DESCRIPTION
        For the analyzer's rules. The commands come from the tree's index (Get-IslAstIndex),
        grouped by name without regard to letter case. Only the names given are found, so a
        rule that also wants a command's aliases lists them. A command whose name is not a
        constant, such as & $tool, is never found. The invocations are in document order, also
        when several names are asked for.

    .PARAMETER Ast
        The syntax tree, or the part of it, to search.

    .PARAMETER Name
        One or more command names, such as Read-Host, or Import-Module and ipmo.

    .EXAMPLE
        Find-IslCommand -Ast $ast -Name 'Import-Module', 'ipmo'

        Every call of Import-Module in the script, under either name.

    .INPUTS
        None.

    .OUTPUTS
        System.Management.Automation.Language.CommandAst.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.Language.CommandAst])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Ast,

        [Parameter(Mandatory)]
        [string[]]$Name
    )
    $index = Get-IslAstIndex -Ast $Ast
    $commands = foreach ($commandName in $Name) {
        if ($index.ByCommand.ContainsKey($commandName)) { $index.ByCommand[$commandName] }
    }
    if ($Name.Count -gt 1) { $commands = $commands | Sort-Object -Property { $_.Extent.StartOffset } }
    $commands
}
