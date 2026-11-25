function Resolve-IslAccount {
    <#
    .SYNOPSIS
        Finds what Windows itself calls the account a credential names, and its SID.

    .DESCRIPTION
        A credential can name an account several ways and Windows shows only one of them. For a
        Microsoft Entra account on a joined device (lab device, 2026-10-05; Findings, "The harness
        as another account"):

            signed in as    isl-verylongusername-test01@4nlnm3.onmicrosoft.com
            display name    Isl Verylongdisplayname Testaccount
            Windows name    AzureAD\IslVerylongdisplayna

        The Windows name is the display name without its spaces, cut at 20 characters, and it is
        what "query user" lists, what owns the session's processes and the only name a scheduled
        task accepted for an interactive principal: the sign-in name and the SID were both refused
        there. The sign-in name resolves to the account's SID only with the AzureAD\ prefix.

        So the name is looked up as given and, when it is a sign-in name without a domain part
        that does not resolve, again as AzureAD\<name>. The SID is then turned back into the name
        Windows uses. Returns nothing when neither lookup resolves; the caller then works with
        the name as it was given.

    .PARAMETER Name
        The account as the credential names it: isl-user, MACHINE\isl-user, DOMAIN\user,
        user@domain or AzureAD\user@domain.

    .EXAMPLE
        Resolve-IslAccount -Name 'someone@contoso.com'

        Name AzureAD\SomeOne and the account's SID, on a device where that Entra user has signed in.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.Account')]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $candidates = @($Name)
    if ($Name -match '@' -and $Name -notmatch '\\') { $candidates += "AzureAD\$Name" }
    foreach ($candidate in $candidates) {
        $account = ConvertTo-IslAccount -Name $candidate
        if ($account) { return $account }
    }
}
