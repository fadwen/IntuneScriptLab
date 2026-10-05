function Get-IslDesktopModulePath {
    <#
    .SYNOPSIS
        The PSModulePath a child process should get: this session's, without PowerShell 7's own folders.

    .DESCRIPTION
        A process started from PowerShell 7 inherits its PSModulePath, which lists PowerShell 7's
        module folders ahead of Windows PowerShell's. A powershell.exe child then loads PowerShell
        7's Microsoft.PowerShell.Management, Utility and Security in place of its own: no Cert:
        drive, and Get-AuthenticodeSignature and ConvertTo-SecureString fail to load. PowerShell 7
        resets the path itself when it starts powershell.exe as a command, but not for a process
        started through System.Diagnostics.Process, which is how the harness starts one.

        The three folders removed are the ones PowerShell 7 adds for itself: $PSHOME\Modules,
        Program Files\PowerShell\Modules and Documents\PowerShell\Modules. Everything else stays in
        its order, so a folder the session added still reaches the child. Under Windows PowerShell
        the path is returned as it is, since $PSHOME\Modules there is the child's own.

    .PARAMETER ModulePath
        The path to filter; the session's PSModulePath when omitted.

    .EXAMPLE
        Get-IslDesktopModulePath

        This session's PSModulePath as a Windows PowerShell child should see it.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()]
        [string]$ModulePath = $env:PSModulePath
    )

    if ($PSVersionTable.PSEdition -ne 'Core') { return $ModulePath }

    $documents = [Environment]::GetFolderPath('MyDocuments')
    $coreOnly = @(
        Join-Path -Path $PSHOME -ChildPath 'Modules'
        if ($env:ProgramFiles) { Join-Path -Path $env:ProgramFiles -ChildPath 'PowerShell\Modules' }
        if ($documents) { Join-Path -Path $documents -ChildPath 'PowerShell\Modules' }
    ) | ForEach-Object { $_.TrimEnd('\') }

    $separator = [System.IO.Path]::PathSeparator
    $kept = foreach ($entry in ($ModulePath -split [regex]::Escape($separator))) {
        if ($entry -and $entry.TrimEnd('\') -notin $coreOnly) { $entry }
    }
    $kept -join $separator
}
