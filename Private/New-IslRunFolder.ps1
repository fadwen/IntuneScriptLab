function New-IslRunFolder {
    <#
    .SYNOPSIS
        Creates the folder that one harness run copies its script or content into.

    .DESCRIPTION
        A run as the current user gets a new folder under the caller's temp folder, which only that
        user and the administrators can open.

        A run as another account cannot reach the caller's temp folder, so its folder is
        ProgramData\IntuneScriptLab\Runs\<id>, and the account is granted Modify on it to read the
        copy and write its output there. ProgramData lets every local user create folders and add
        files below it, and a folder created there inherits that: another user could add a file to
        the run folder, or, having created ProgramData\IntuneScriptLab before the module did, own
        it and replace the run folder, and so change the script that then runs as the account, or
        the output the harness reads back. So IntuneScriptLab and Runs are given an access list
        of their own that is not inherited: full control for SYSTEM, the Administrators group and
        the caller, and nothing for anyone else. A level that is a link to another place, or that
        is owned by anyone but SYSTEM, the Administrators group or the caller, is not changed; the
        run is refused with an error that names it, so that whoever runs the harness can remove it.

    .PARAMETER Account
        The account the run is for, as the credential names it. Omit it for a run as the current
        user.

    .EXAMPLE
        New-IslRunFolder -Account 'isl-user'

        Returns C:\ProgramData\IntuneScriptLab\Runs\<id>, which isl-user can modify and no other
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
    $moduleFolder = Join-Path -Path $env:ProgramData -ChildPath 'IntuneScriptLab'
    $runsFolder = Join-Path -Path $moduleFolder -ChildPath 'Runs'
    $folder = Join-Path -Path $runsFolder -ChildPath $runId
    try {
        foreach ($level in $moduleFolder, $runsFolder) {
            $null = New-Item -ItemType Directory -Path $level -Force -ErrorAction Stop @script:IslInternal
            $item = Get-Item -LiteralPath $level -Force -ErrorAction Stop
            $problem = $null
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                $problem = 'is a link to another folder'
            } else {
                $owner = (Get-Acl -LiteralPath $level -ErrorAction Stop).GetOwner(
                    [System.Security.Principal.SecurityIdentifier]).Value
                if ($owner -notin $trusted) {
                    $problem = "is owned by $owner, not by SYSTEM, the Administrators group or the caller"
                }
            }
            if ($problem) {
                $recordSplat = @{
                    Message = ("The run folder's parent $level $problem, so another user could change " +
                        'what runs as the account. Remove the folder and run again.')
                    ErrorId = 'RunFolderUnsafe'
                    Category = [System.Management.Automation.ErrorCategory]::SecurityError
                    TargetObject = $level
                }
                $PSCmdlet.ThrowTerminatingError((New-IslErrorRecord @recordSplat))
            }

            $grants = foreach ($sid in $trusted) { '"*{0}:(OI)(CI)F"' -f $sid }
            $arguments = '"{0}" /inheritance:r /grant:r {1}' -f $level, ($grants -join ' ')
            $result = Invoke-IslNativeCommand -FilePath $icacls -Arguments $arguments
            if ($result.ExitCode -ne 0) {
                $output = @($result.StdErr, $result.StdOut | Where-Object { $_ }) -join ' '
                $recordSplat = @{
                    Message = "Could not restrict access to ${level}: $output"
                    ErrorId = 'RunFolderNotRestricted'
                    Category = [System.Management.Automation.ErrorCategory]::PermissionDenied
                    TargetObject = $level
                }
                $PSCmdlet.ThrowTerminatingError((New-IslErrorRecord @recordSplat))
            }
        }

        # The run's own folder inherits the access list of Runs, and the account is added to it
        $null = New-Item -ItemType Directory -Path $folder -ErrorAction Stop @script:IslInternal
        Grant-IslFolderAccess -Path $folder -Account $Account
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }

    $folder
}
