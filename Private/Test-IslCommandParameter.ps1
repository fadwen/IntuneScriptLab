function Test-IslCommandParameter {
    <#
    .SYNOPSIS
        True when the command is called with the named parameter (prefix match, like PowerShell).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.CommandAst]$Command,

        [Parameter(Mandatory)]
        [string]$ParameterName
    )
    foreach ($element in $Command.CommandElements) {
        $isParameter = $element.GetType().Name -eq 'CommandParameterAst'
        if ($isParameter -and $ParameterName.StartsWith($element.ParameterName, 'OrdinalIgnoreCase')) {
            return $true
        }
    }
    $false
}
