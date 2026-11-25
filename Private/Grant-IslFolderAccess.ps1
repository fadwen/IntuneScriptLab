function Grant-IslFolderAccess {
    <#
    .SYNOPSIS
        Gives an account Modify on what is in a folder, and the right to add to it.

    .DESCRIPTION
        The harness runs another account's script from a cache folder and reads that account's
        output files back from it, so the account needs to read the script copy and write next to
        it. It gets Modify on what is in the folder and what is created there, inherited and not
        on the folder itself, and on the folder itself the rights to list, read and traverse it and
        to add files and folders. It gets no Delete there, so it cannot rename the folder and put
        another in its place. Uses icacls, which resolves the account name the way the scheduled
        task will. A separate function so the unit tests can mock the grant for accounts that do
        not exist.

    .PARAMETER Path
        The folder.

    .PARAMETER Account
        The account, as the credential names it (isl-user, MACHINE\isl-user or user@domain).

    .EXAMPLE
        Grant-IslFolderAccess -Path C:\ProgramData\IntuneScriptLab\Runs\abc -Account isl-user

        Modify on the folder's contents, and list, read and add on the folder itself, for isl-user.

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
    # (OI)(CI)(IO)M: Modify on everything below, not on the folder. The folder itself: list (RD),
    # read its attributes (RA, REA) and access list (RC), traverse (X), synchronize (S), add files
    # (WD) and folders (AD)
    $arguments = '"{0}" /grant "{1}:(OI)(CI)(IO)M" "{1}:(RD,RA,REA,RC,X,S,WD,AD)"' -f $quotedPath, $trustee
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
