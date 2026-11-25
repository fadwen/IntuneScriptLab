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

    function script:Assert-RunGrant {
        <#
        .SYNOPSIS
            Asserts the grant an account got on a run folder.

        .DESCRIPTION
            Reads the entries set on the folder itself for the identity, and asserts that one gives
            Modify to what is in the folder only (inherit-only, to files and folders), that one lets
            it list the folder and add files and folders, and that none of the entries that apply to
            the folder itself lets it delete the folder or what is in it. Each failure lists every
            entry of the identity, so that an entry Windows added can be read from the log.

        .PARAMETER Path
            The folder.

        .PARAMETER Identity
            The identity, as the access list names it.

        .EXAMPLE
            Assert-RunGrant -Path $script:Folder -Identity $script:Me.Name

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
            [string]$Identity
        )

        $rules = @((Get-Acl -LiteralPath $Path).Access | Where-Object {
                -not $_.IsInherited -and "$($_.IdentityReference)" -eq $Identity
            })
        $listed = ($rules | ForEach-Object {
                $flags = '{0}/{1}' -f $_.InheritanceFlags, $_.PropagationFlags
                '{0} {1} {2}' -f $_.FileSystemRights, $flags, $_.AccessControlType
            }) -join '; '
        $because = "the entries of $Identity are: $listed"

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
        Grant-Access -Path $script:Folder -Account $script:Me.Name
        Assert-RunGrant -Path $script:Folder -Identity $script:Me.Name
    }

    It 'grants on a folder path that ends in a backslash' {
        # Before, the backslash escaped the closing quote and icacls was handed a path with the rest
        # of the arguments in it: "The filename, directory name, or volume label syntax is incorrect"
        Mock Resolve-IslAccount -ModuleName IntuneScriptLab { }
        Grant-Access -Path "$($script:Folder)\" -Account $script:Me.Name
        Assert-RunGrant -Path $script:Folder -Identity $script:Me.Name
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
