function Grant-IslFolderAccess {
    <#
    .SYNOPSIS
        Gives an account Modify rights on a folder and everything created in it.

    .DESCRIPTION
        The harness runs another account's script from a cache folder and reads that account's
        output files back from it, so the account needs to read the script copy and write next to
        it. Uses icacls, which resolves the account name the way the scheduled task will. A
        separate function so the unit tests can mock the grant for accounts that do not exist.

    .PARAMETER Path
        The folder.

    .PARAMETER Account
        The account, as the credential names it (isl-user, MACHINE\isl-user or user@domain).

    .EXAMPLE
        Grant-IslFolderAccess -Path C:\ProgramData\IntuneScriptLab\Runs\abc -Account isl-user

        Modify, inherited by files and subfolders, for isl-user.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Account
    )

    $output = & icacls.exe $Path /grant "${Account}:(OI)(CI)M" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Could not grant $Account access to ${Path}: $($output -join ' ')"
    }
}
