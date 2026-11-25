function ConvertTo-IslAccount {
    <#
    .SYNOPSIS
        Gets the SID behind an account name, and the name Windows gives that SID.

    .DESCRIPTION
        The two translations Resolve-IslAccount is built on, kept apart so the unit tests can stand
        in for accounts a build machine does not have. Returns nothing for a name Windows cannot
        resolve, and nothing off Windows.

    .PARAMETER Name
        One account name, exactly as it is to be looked up.

    .EXAMPLE
        ConvertTo-IslAccount -Name 'NT AUTHORITY\SYSTEM'

        Name NT AUTHORITY\SYSTEM, Sid S-1-5-18.

    .INPUTS
        None.

    .OUTPUTS
        IntuneScriptLab.Account.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.Account')]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    try {
        $sidType = [System.Security.Principal.SecurityIdentifier]
        $sid = ([System.Security.Principal.NTAccount]$Name).Translate($sidType)
        [pscustomobject]@{
            PSTypeName = 'IntuneScriptLab.Account'
            Name = $sid.Translate([System.Security.Principal.NTAccount]).Value
            Sid = $sid.Value
        }
    } catch { Write-Verbose "Account name '$Name' not resolved: $($_.Exception.Message)" }
}
