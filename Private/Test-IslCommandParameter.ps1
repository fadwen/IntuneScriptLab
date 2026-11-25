function Test-IslCommandParameter {
    <#
    .SYNOPSIS
        Tells whether a command invocation passes the named parameter.

    .DESCRIPTION
        For the analyzer's rules. A parameter written as a prefix of the name counts: -ErrorA
        matches ErrorAction. Unlike PowerShell, which refuses a prefix that fits two parameters,
        it does not check for ambiguity, so -Error matches both ErrorAction and ErrorVariable.
        The comparison ignores letter case. Only parameters written by name count; a value passed by position does not.

    .PARAMETER Command
        The command invocation.

    .PARAMETER ParameterName
        The parameter's full name, without the dash, such as ErrorAction.

    .EXAMPLE
        Test-IslCommandParameter -Command $command -ParameterName 'ErrorAction'

        $true for Get-Item C:\a -ErrorAction Stop.

    .INPUTS
        None.

    .OUTPUTS
        System.Boolean.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
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
