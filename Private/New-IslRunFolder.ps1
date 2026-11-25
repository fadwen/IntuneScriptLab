function New-IslRunFolder {
    <#
    .SYNOPSIS
        Creates the folder that one harness run copies its script or content into.

    .DESCRIPTION
        A run as the current user gets a new folder under the caller's temp folder, which only that
        user and the administrators can open.

        A run as another account cannot reach the caller's temp folder, so its folder is
        ProgramData\IntuneScriptLabRuns\<id>, and the account is granted Modify on it to read the
        copy and write its output there. ProgramData lets every local user create folders and add
        files below it, and a folder created there inherits that: another user could add a file to
        the run folder, or, having created the parent folder before the module did, own it and
        replace the run folder, and so change the script that then runs as the account, or the
        output the harness reads back. So IntuneScriptLabRuns is given an access list of its own
        that is not inherited: full control for SYSTEM, the Administrators group and the caller,
        and nothing for anyone else, an entry that was there before for another account included.
        A folder that is a link to another place, or that is owned by anyone but SYSTEM, the
        Administrators group or the caller, is not changed; the run is refused with an error that
        names it, so that whoever runs the harness can remove it.

        The folder is not under ProgramData\IntuneScriptLab, because the validation kit gives every
        user Modify there for its probes, and with it the right to rename that folder and put
        another in its place.
    .PARAMETER Account
        The account the run is for, as the credential names it. Omit it for a run as the current
        user.

    .EXAMPLE
        New-IslRunFolder -Account 'isl-user'

        Returns C:\ProgramData\IntuneScriptLabRuns\<id>, which isl-user can modify and no other
        user but the caller and the administrators can open.

    .EXAMPLE
        New-IslRunFolder

        Returns a new folder under the caller's temp folder.

    .INPUTS
        None.

    .OUTPUTS
        System.String. The full path of the folder.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Bookkeeping of a run that the command which started it has already asked about.')]
    param(
        [Parameter()]
        [string]$Account
    )

    $runId = [guid]::NewGuid().ToString('N')
    if (-not $Account) {
        $folder = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "IntuneScriptLab\$runId"
        try {
            $null = New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop @script:IslInternal
        } catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
        return $folder
    }

    $callerSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    # SYSTEM, BUILTIN\Administrators and the caller: who may own the folders, and who may open them
    $trusted = @('S-1-5-18', 'S-1-5-32-544', $callerSid)
    $icacls = Join-Path -Path ([System.Environment]::SystemDirectory) -ChildPath 'icacls.exe'
    $runsFolder = Join-Path -Path $env:ProgramData -ChildPath 'IntuneScriptLabRuns'
    $folder = Join-Path -Path $runsFolder -ChildPath $runId
    try {
        $null = New-Item -ItemType Directory -Path $runsFolder -Force -ErrorAction Stop @script:IslInternal
        $item = Get-Item -LiteralPath $runsFolder -Force -ErrorAction Stop
        $problem = $null
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            $problem = 'is a link to another folder'
        } else {
            $owner = (Get-Acl -LiteralPath $runsFolder -ErrorAction Stop).GetOwner(
                [System.Security.Principal.SecurityIdentifier]).Value
            if ($owner -notin $trusted) {
                $problem = "is owned by $owner, not by SYSTEM, the Administrators group or the caller"
            }
        }
        if ($problem) {
            $recordSplat = @{
                Message = ("The folder of the runs, $runsFolder, $problem, so another user could change " +
                    'what runs as the account. Remove the folder and run again.')
                ErrorId = 'RunFolderUnsafe'
                Category = [System.Management.Automation.ErrorCategory]::SecurityError
                TargetObject = $runsFolder
            }
            $PSCmdlet.ThrowTerminatingError((New-IslErrorRecord @recordSplat))
        }

        # Inheritance off and the three grants first, so the folder is never open while it changes;
        # then every entry for another account that was set on the folder itself is removed
        $grants = foreach ($sid in $trusted) { '"*{0}:(OI)(CI)F"' -f $sid }
        $restrictions = @('"{0}" /inheritance:r /grant:r {1}' -f $runsFolder, ($grants -join ' '))
        $acl = Get-Acl -LiteralPath $runsFolder -ErrorAction Stop
        $sidType = [System.Security.Principal.SecurityIdentifier]
        $others = @($acl.GetAccessRules($true, $false, $sidType) |
                ForEach-Object { $_.IdentityReference.Value } |
                Where-Object { $_ -notin $trusted } |
                Sort-Object -Unique)
        foreach ($sid in $others) {
            $restrictions += '"{0}" /remove "*{1}"' -f $runsFolder, $sid
        }
        foreach ($arguments in $restrictions) {
            $result = Invoke-IslNativeCommand -FilePath $icacls -Arguments $arguments
            if ($result.ExitCode -ne 0) {
                $output = @($result.StdErr, $result.StdOut | Where-Object { $_ }) -join ' '
                $recordSplat = @{
                    Message = "Could not restrict access to ${runsFolder}: $output"
                    ErrorId = 'RunFolderNotRestricted'
                    Category = [System.Management.Automation.ErrorCategory]::PermissionDenied
                    TargetObject = $runsFolder
                }
                $PSCmdlet.ThrowTerminatingError((New-IslErrorRecord @recordSplat))
            }
        }

        # The run's own folder inherits that access list, and the account is added to it
        $null = New-Item -ItemType Directory -Path $folder -ErrorAction Stop @script:IslInternal
        Grant-IslFolderAccess -Path $folder -Account $Account
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }

    $folder
}
