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

    .INPUTS
        None.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Account
    )

    # By SID where Windows can resolve the name: a sign-in name of an Entra account is not a name
    # icacls looks up
    $resolved = Resolve-IslAccount -Name $Account
    $trustee = if ($resolved) { "*$($resolved.Sid)" } else { $Account }
    # Windows PowerShell turns a native command's redirected stderr into error records, and under
    # a caller's -ErrorAction Stop the first one ends the function with icacls' bare line instead
    # of the message below. Invoke-IslNativeCommand reads the streams without that
    $icacls = Join-Path -Path ([System.Environment]::SystemDirectory) -ChildPath 'icacls.exe'
    # A backslash before a closing quote escapes the quote when a program parses its command line,
    # so a path that ends in one would swallow the rest of the arguments. Doubled, the backslashes
    # stand for themselves; trimmed, C:\ would become C:, the current folder of that drive
    $quotedPath = $Path -replace '(\\+)$', '$1$1'
    $arguments = '"{0}" /grant "{1}:(OI)(CI)M"' -f $quotedPath, $trustee
    try {
        $result = Invoke-IslNativeCommand -FilePath $icacls -Arguments $arguments
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }

    if ($result.ExitCode -ne 0) {
        # icacls writes the reason to its error stream and a count of files to its output
        $output = @($result.StdErr, $result.StdOut | Where-Object { $_ }) -join ' '
        $recordSplat = @{
            Message = "Could not grant $Account access to ${Path}: $output"
            ErrorId = 'FolderAccessNotGranted'
            Category = [System.Management.Automation.ErrorCategory]::PermissionDenied
            TargetObject = $Path
        }
        $PSCmdlet.ThrowTerminatingError((New-IslErrorRecord @recordSplat))
    }
}
