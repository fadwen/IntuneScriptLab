function Get-IslLogonSession {
    <#
    .SYNOPSIS
        Lists the logon sessions with a desktop on this machine: user, SID and session id.

    .DESCRIPTION
        The agent runs user-context scripts inside the signed-in user's own session (session 2,
        UserInteractive true, on the lab device: REM-PROBE-USER64), so the harness needs to know
        whether the account it is asked to run as holds a session before it chooses between an
        interactive scheduled task and a stored-password one.

        A session with a desktop runs explorer.exe, or sihost.exe while the desktop is still
        starting; the owner of that process is the session's user, and its SID is what the
        credential's account is matched on. Earlier versions parsed "query user", which is not on
        Windows Home editions and prints localized text. Reading another account's process owner
        needs an elevated session, which the credential launch needs anyway; a process whose owner
        cannot be read is left out.

    .EXAMPLE
        Get-IslLogonSession | Where-Object Sid -eq $account.Sid

        The session of that account, if it has one.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.LogonSession')]
    param()

    $filter = "Name='explorer.exe' OR Name='sihost.exe'"
    $shells = @(Get-CimInstance -ClassName Win32_Process -Filter $filter -ErrorAction SilentlyContinue)
    $seen = @{}
    foreach ($shell in ($shells | Sort-Object -Property SessionId, Name)) {
        $owner = Invoke-CimMethod -InputObject $shell -MethodName GetOwner -ErrorAction SilentlyContinue
        $sid = (Invoke-CimMethod -InputObject $shell -MethodName GetOwnerSid -ErrorAction SilentlyContinue).Sid
        if (-not $sid -or -not $owner.User) { continue }
        $key = "$($shell.SessionId)|$sid"
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        [pscustomobject]@{
            PSTypeName = 'IntuneScriptLab.LogonSession'
            UserName   = $owner.User
            Domain     = $owner.Domain
            Sid        = $sid
            Id         = [int]$shell.SessionId
        }
    }
}
