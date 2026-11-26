#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The grant on the run folder another account's script is copied to. By SID where Windows can
    resolve the account, because the sign-in name of an Entra account is not a name icacls looks up
    (VM 125, 2026-10-05); by the name as given otherwise.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }
    $script:Me = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    # An account on no folder of the tests, granted by name. Not the account that runs them: on a
    # hosted runner it owns its test folder, and a grant to it there also writes FullControl for it
    $script:Stranger = 'NT AUTHORITY\LOCAL SERVICE'

    function Grant-Access {
        <#
        .SYNOPSIS
            Grants an account access to a folder with the module's private function.

        .DESCRIPTION
            Calls Grant-IslFolderAccess inside the module with the error preference set first, so
            that a test can show what the function does under the preference a caller's
            -ErrorAction leaves in force.

        .PARAMETER Path
            The folder to grant access to.

        .PARAMETER Account
            The name of the account that is given access.

        .PARAMETER Preference
            The error action preference in force inside the module, Continue by default.

        .EXAMPLE
            Grant-Access -Path $script:Folder -Account $script:Me.Name

            Grants the current user access to the test folder.

        .INPUTS
            None.

        .OUTPUTS
            System.Void. The function writes nothing.
        #>
        [CmdletBinding()]
        [OutputType([void])]
        param(
            [string]$Path,

            [string]$Account,

            [string]$Preference = 'Continue'
        )

        $parameters = @{ Path = $Path; Account = $Account; Preference = $Preference }
        InModuleScope IntuneScriptLab -Parameters $parameters {
            # What a caller's -ErrorAction leaves in force inside the module
            $ErrorActionPreference = $Preference
            Grant-IslFolderAccess -Path $Path -Account $Account
        }
    }

    function script:Get-GrantEntry {
        <#
        .SYNOPSIS
            Gets an identity's own entries on a folder, each with a text that names it.

        .DESCRIPTION
            Returns the entries of the folder's access list that are set on it, not inherited, for
            the identity, each with a Text of its rights, inheritance and propagation flags and
            type, so that the entries before and after a grant can be compared.

        .PARAMETER Path
            The folder.

        .PARAMETER Identity
            The identity, as the access list names it.

        .EXAMPLE
            $before = @(Get-GrantEntry -Path $script:Folder -Identity $script:Me.Name).Text

            The texts of the current user's entries on the test folder.

        .INPUTS
            None.

        .OUTPUTS
            System.Security.AccessControl.FileSystemAccessRule, with a Text note property.
        #>
        [CmdletBinding()]
        [OutputType([System.Security.AccessControl.FileSystemAccessRule])]
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter(Mandatory)]
            [string]$Identity
        )

        foreach ($rule in (Get-Acl -LiteralPath $Path).Access) {
            if ($rule.IsInherited -or "$($rule.IdentityReference)" -ne $Identity) {
                continue
            }
            $flags = '{0}/{1}' -f $rule.InheritanceFlags, $rule.PropagationFlags
            $text = '{0} {1} {2}' -f $rule.FileSystemRights, $flags, $rule.AccessControlType
            $rule | Add-Member -MemberType NoteProperty -Name Text -Value $text -PassThru
        }
    }

    function script:Assert-RunGrant {
        <#
        .SYNOPSIS
            Asserts the grant an account got on a run folder.

        .DESCRIPTION
            Reads the entries set on the folder itself for the identity that were not there before
            the grant, and asserts that one gives Modify to what is in the folder only
            (inherit-only, to files and folders), that one lets it list the folder and add files and
            folders, and that none of them lets it delete the folder or what is in it. The test
            grants to the account that runs it, which already has full control of its own test
            folder on a hosted runner, so the entries from before are left out. Each failure lists
            the entries the grant added.

        .PARAMETER Path
            The folder.

        .PARAMETER Identity
            The identity, as the access list names it.

        .PARAMETER Before
            The identity's entries before the grant, as Get-GrantEntry returned them.

        .EXAMPLE
            Assert-RunGrant -Path $script:Folder -Identity $script:Me.Name -Before $before

            Asserts the grant of the current user on the test folder.

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
            [string]$Identity,

            [Parameter()]
            [AllowEmptyCollection()]
            [string[]]$Before = @()
        )

        $rules = @(Get-GrantEntry -Path $Path -Identity $Identity | Where-Object { $_.Text -notin $Before })
        $because = "the entries the grant added for $Identity are: $(($rules.Text) -join '; ')"

        $below = @($rules | Where-Object {
                "$($_.PropagationFlags)" -eq 'InheritOnly' -and "$($_.FileSystemRights)" -like '*Modify*'
            })
        $below.Count | Should-BeGreaterThan 0 -Because $because
        $adding = [System.Security.AccessControl.FileSystemRights]'ListDirectory, CreateFiles, CreateDirectories'
        $onFolder = @($rules | Where-Object { "$($_.PropagationFlags)" -ne 'InheritOnly' })
        @($onFolder | Where-Object { ($_.FileSystemRights -band $adding) -eq $adding }).Count |
            Should-BeGreaterThan 0 -Because $because
        $deleting = [System.Security.AccessControl.FileSystemRights]'Delete, DeleteSubdirectoriesAndFiles'
        @($onFolder | Where-Object {
                "$($_.AccessControlType)" -eq 'Allow' -and [int]($_.FileSystemRights -band $deleting) -ne 0
            }).Count | Should-Be 0 -Because $because
    }
}

Describe 'Grant-IslFolderAccess' -Tag 'Unit', 'Private' {

    BeforeEach {
        $script:Folder = Join-Path $TestDrive "run-$([guid]::NewGuid().ToString('N'))"
        $null = New-Item -ItemType Directory -Path $script:Folder
    }

    It 'grants Modify on what is in the folder, and no Delete on the folder, by the SID Windows resolves' {
        Mock Resolve-IslAccount -ModuleName IntuneScriptLab {
            [pscustomobject]@{ Name = 'AzureAD\IslVerylongdisplayna'; Sid = 'S-1-5-32-545' }
        }
        # S-1-5-32-545 is BUILTIN\Users, standing in for the account: the grant has to land on the
        # SID it was given, whatever the name passed in
        Grant-Access -Path $script:Folder -Account 'isl-verylongusername-test01@4nlnm3.onmicrosoft.com'
        $sidType = [System.Security.Principal.SecurityIdentifier]
        $rules = @((Get-Acl -Path $script:Folder).Access | Where-Object {
                -not $_.IsInherited -and $_.IdentityReference.Translate($sidType).Value -eq 'S-1-5-32-545'
            })
        $rules | Should-BeCollection -Count 2
        $below = @($rules | Where-Object { "$($_.PropagationFlags)" -eq 'InheritOnly' })
        $below | Should-BeCollection -Count 1
        "$($below[0].FileSystemRights)" | Should-BeLikeString '*Modify*'
        "$($below[0].InheritanceFlags)" | Should-Be 'ContainerInherit, ObjectInherit'
        $itself = @($rules | Where-Object { "$($_.InheritanceFlags)" -eq 'None' })
        $itself | Should-BeCollection -Count 1
        $rights = $itself[0].FileSystemRights
        # Listing and adding, which the run needs; deleting or renaming the folder, which it must not
        $wanted = [System.Security.AccessControl.FileSystemRights]'ListDirectory, CreateFiles, CreateDirectories'
        ($rights -band $wanted) | Should-Be $wanted
        $deleting = [System.Security.AccessControl.FileSystemRights]'Delete, DeleteSubdirectoriesAndFiles'
        [int]($rights -band $deleting) | Should-Be 0
    }

    It 'grants by the name as given when Windows does not resolve it' {
        Mock Resolve-IslAccount -ModuleName IntuneScriptLab { }
        $before = @(Get-GrantEntry -Path $script:Folder -Identity $script:Stranger | ForEach-Object { $_.Text })
        Grant-Access -Path $script:Folder -Account $script:Stranger
        Assert-RunGrant -Path $script:Folder -Identity $script:Stranger -Before $before
    }

    It 'grants on a folder path that ends in a backslash' {
        # Before, the backslash escaped the closing quote and icacls was handed a path with the rest
        # of the arguments in it: "The filename, directory name, or volume label syntax is incorrect"
        Mock Resolve-IslAccount -ModuleName IntuneScriptLab { }
        $before = @(Get-GrantEntry -Path $script:Folder -Identity $script:Stranger | ForEach-Object { $_.Text })
        Grant-Access -Path "$($script:Folder)\" -Account $script:Stranger
        Assert-RunGrant -Path $script:Folder -Identity $script:Stranger -Before $before
    }

    It 'names the account and the folder when icacls refuses, under error action <Preference>' -ForEach @(
        @{ Preference = 'Continue' }
        @{ Preference = 'Stop' }
    ) {
        # Under Stop, Windows PowerShell 5.1 ended the function at icacls' first stderr line with
        # that line alone as the message (the CI runner and the lab device both showed it)
        Mock Resolve-IslAccount -ModuleName IntuneScriptLab { }
        $missing = "$env:COMPUTERNAME\no-such-account-for-isl"
        $failure = { Grant-Access -Path $script:Folder -Account $missing -Preference $Preference } | Should-Throw
        $failure.Exception.Message | Should-BeLikeString "Could not grant $missing access to *No mapping*"
        $failure.FullyQualifiedErrorId | Should-BeLikeString 'FolderAccessNotGranted,*'
    }
}
