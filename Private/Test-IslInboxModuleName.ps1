function Test-IslInboxModuleName {
    <#
    .SYNOPSIS
    Tells whether a module name that a script uses is one the agent's SYSTEM session has.

    .DESCRIPTION
    For the module-dependency rule. A name is in-box when it is in the list of modules that come
    with Windows (Get-IslInboxModule). A path, a name that ends in .psm1, .ps1 or .psd1, and a name
    with a wildcard or a variable in it count as in-box as well: a path is a file the script ships
    or references, which the relative-path rule looks at, and a pattern cannot be told apart here.

    .PARAMETER Name
    The module name as the script writes it.

    .PARAMETER InboxModule
    The names of the in-box modules.

    .EXAMPLE
    Test-IslInboxModuleName -Name 'Microsoft.Graph.Authentication' -InboxModule (Get-IslInboxModule)

    $false: the Graph SDK is not in-box.

    .INPUTS
    None.

    .OUTPUTS
    System.Boolean.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Name,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$InboxModule
    )

    # A path is a file the script ships or references, not a module by name; leave it to the
    # relative-path rule
    if ($Name -match '[\\/]' -or $Name -match '\.psm?1$|\.psd1$') { return $true }
    if ($Name -match '[\*\?\$]') { return $true }
    $Name -in $InboxModule
}
