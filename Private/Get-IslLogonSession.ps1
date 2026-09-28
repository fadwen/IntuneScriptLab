function Get-IslLogonSession {
    <#
    .SYNOPSIS
        Lists the interactive logon sessions on this machine: user, session name, id and state.

    .DESCRIPTION
        Parses "query user". The agent runs user-context scripts inside the signed-in user's own
        session (session 2, UserInteractive true, on the lab device: REM-PROBE-USER64), so the
        harness needs to know whether the account it is asked to run as holds a session before it
        chooses between an interactive scheduled task and a stored-password one.

        The columns are separated by runs of spaces; a disconnected session prints no session
        name, and the current session is marked with a leading ">".

    .EXAMPLE
        Get-IslLogonSession | Where-Object UserName -eq 'isl-user'

        The session of that account, if it has one.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.LogonSession')]
    param()

    $lines = @(Get-IslQueryUserOutput)
    $sessions = foreach ($line in ($lines | Select-Object -Skip 1)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = @($line.Trim().TrimStart('>').Trim() -split '\s{2,}')
        # user, session name, id, state, idle, logon time; a disconnected session has no name
        if ($parts.Count -ge 6 -and $parts[2] -match '^\d+$') {
            $userName, $sessionName, $id, $state = $parts[0], $parts[1], $parts[2], $parts[3]
        }
        elseif ($parts.Count -ge 5 -and $parts[1] -match '^\d+$') {
            $userName, $sessionName, $id, $state = $parts[0], '', $parts[1], $parts[2]
        }
        else { continue }
        [pscustomobject]@{
            PSTypeName  = 'IntuneScriptLab.LogonSession'
            UserName    = $userName
            SessionName = $sessionName
            Id          = [int]$id
            State       = $state
        }
    }
    @($sessions)
}
