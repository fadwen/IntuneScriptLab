function Find-IslCommand {
    <#
    .SYNOPSIS
        Finds command invocations by name (case-insensitive), including aliases the caller lists.
    #>
    [CmdletBinding()]
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
