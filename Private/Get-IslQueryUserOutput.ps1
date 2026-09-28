function Get-IslQueryUserOutput {
    <#
    .SYNOPSIS
        Returns the lines of "query user", or nothing where the tool is missing or nobody is logged on.

    .DESCRIPTION
        Separated from Get-IslLogonSession so the parser can be tested with fixed text. query.exe
        writes "No User exists for *" to stderr and exits 1 when no session exists; that is an empty
        result here, not an error.

    .EXAMPLE
        Get-IslQueryUserOutput

        The header line and one line per session, as query.exe prints them.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    $query = Get-Command -Name query.exe -ErrorAction SilentlyContinue
    if (-not $query) { return @() }
    @(& $query.Source user 2>$null | ForEach-Object { "$_" })
}
