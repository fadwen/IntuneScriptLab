function Test-IslFilterConnector {
    <#
    .SYNOPSIS
    Tells whether the filter token at the parser's cursor is a given connector.

    .DESCRIPTION
    For the assignment filter parser. The token is the connector when it is a word whose text,
    without a leading dash, is the name: and, -and, or and -or all count. The comparison is that
    of PowerShell's -eq, which ignores letter case. The cursor does not move.

    .PARAMETER Parser
    The parser state from New-IslFilterParser.

    .PARAMETER Name
    The connector without a dash, and or or.

    .EXAMPLE
    Test-IslFilterConnector -Parser $parser -Name 'and'

    $true when the next token is and or -and.

    .INPUTS
    None.

    .OUTPUTS
    System.Boolean.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Parser,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $token = Get-IslFilterToken -Parser $Parser
    [bool]($token -and $token.Type -eq 'word' -and ($token.Text -replace '^-', '') -eq $Name)
}
