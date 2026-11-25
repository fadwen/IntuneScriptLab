function New-IslRunFolder {
    <#
    .SYNOPSIS
        Creates the folder that one harness run copies its script or content into.

    .DESCRIPTION
        A run as the current user gets a new folder under the caller's temp folder, which only that
        user and the administrators can open.

        A run as another account cannot reach the caller's temp folder, so its folder is
        ProgramData\IntuneScriptLabRun-<id>, and the account is granted Modify on it to read the
        copy and write its output there. ProgramData lets every local user create folders and add
        files below it, and a folder created there inherits that, so another user could change the
        script that then runs as the account, or the output the harness reads back. The folder is
        therefore created with an access list of its own in the same call that creates it: full
        control for SYSTEM, the Administrators group and the caller, nothing inherited, and so no
        moment at which another user may write to it. Its name is new for each run, so no other
        user can create it first and keep the runs from starting, as a fixed name would let them.

        The folder is refused, with an error that names it, when something is already there under
        the name, or when after its creation it is not owned by SYSTEM, the Administrators group or
        the caller, or its access list is not its own: either means another user got there first.

        The folder is not under ProgramData\IntuneScriptLab, because the validation kit gives every
        user Modify there for its probes, and with it the right to rename that folder and put
        another in its place.

    .PARAMETER Account
        The account the run is for, as the credential names it. Omit it for a run as the current
        user.

    .PARAMETER RunId
        The id in the folder's name. A new GUID by default; the unit tests give one so that they
        can put something in the folder's place first.

    .EXAMPLE
        New-IslRunFolder -Account 'isl-user'

        Returns C:\ProgramData\IntuneScriptLabRun-<id>, which isl-user can modify and no other
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
        [string]$Account,

        [Parameter()]
        [ValidatePattern('\A[0-9a-f]{32}\z')]
        [string]$RunId = [guid]::NewGuid().ToString('N')
    )

    if (-not $Account) {
        $folder = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "IntuneScriptLab\$RunId"
        try {
            $null = New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop @script:IslInternal
        } catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
        return $folder
    }

    $callerSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    # SYSTEM, BUILTIN\Administrators and the caller: who may own the folder, and who may open it
    $trusted = @('S-1-5-18', 'S-1-5-32-544', $callerSid)
    $folder = Join-Path -Path $env:ProgramData -ChildPath "IntuneScriptLabRun-$RunId"
    $problem = $null
    try {
        if (Test-Path -LiteralPath $folder) {
            $problem = 'is already there'
        } else {
            $security = [System.Security.AccessControl.DirectorySecurity]::new()
            # Protected: nothing is inherited from ProgramData, now or later
            $security.SetAccessRuleProtection($true, $false)
            $inheritance = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
            foreach ($sid in $trusted) {
                $rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
                    [System.Security.Principal.SecurityIdentifier]::new($sid),
                    [System.Security.AccessControl.FileSystemRights]::FullControl, $inheritance,
                    [System.Security.AccessControl.PropagationFlags]::None,
                    [System.Security.AccessControl.AccessControlType]::Allow)
                $security.AddAccessRule($rule)
            }
            # .NET creates the folder with the access list in one call. Both calls also return a
            # folder that was already there, which the checks below then refuse
            $aclExtensions = 'System.IO.FileSystemAclExtensions' -as [type]
            if ($aclExtensions) {
                $null = $aclExtensions::Create([System.IO.DirectoryInfo]::new($folder), $security)
            } else {
                $null = [System.IO.Directory]::CreateDirectory($folder, $security)
            }

            $item = Get-Item -LiteralPath $folder -Force -ErrorAction Stop
            $acl = Get-Acl -LiteralPath $folder -ErrorAction Stop
            $owner = $acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                $problem = 'is a link to another folder'
            } elseif ($owner -notin $trusted) {
                $problem = "is owned by $owner, not by SYSTEM, the Administrators group or the caller"
            } elseif (-not $acl.AreAccessRulesProtected) {
                $problem = 'inherits the access of ProgramData'
            }
        }
        if ($problem) {
            $recordSplat = @{
                Message = ("The run folder $folder $problem, so another user could change what runs " +
                    'as the account. Run again; each run takes a new folder name.')
                ErrorId = 'RunFolderUnsafe'
                Category = [System.Management.Automation.ErrorCategory]::SecurityError
                TargetObject = $folder
            }
            $PSCmdlet.ThrowTerminatingError((New-IslErrorRecord @recordSplat))
        }

        Grant-IslFolderAccess -Path $folder -Account $Account
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }

    $folder
}
