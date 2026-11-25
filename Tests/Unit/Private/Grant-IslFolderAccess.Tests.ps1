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
        $rule = (Get-Acl -Path $script:Folder).Access | Where-Object {
            -not $_.IsInherited -and "$($_.IdentityReference)" -eq $script:Me.Name
        }
        # One entry for the folder's contents and one for the folder itself
        @($rule).Count | Should-Be 2
    }

    It 'grants on a folder path that ends in a backslash' {
        # Before, the backslash escaped the closing quote and icacls was handed a path with the rest
        # of the arguments in it: "The filename, directory name, or volume label syntax is incorrect"
        Mock Resolve-IslAccount -ModuleName IntuneScriptLab { }
        Grant-Access -Path "$($script:Folder)\" -Account $script:Me.Name
        $rule = (Get-Acl -Path $script:Folder).Access | Where-Object {
            -not $_.IsInherited -and "$($_.IdentityReference)" -eq $script:Me.Name
        }
        # One entry for the folder's contents and one for the folder itself
        @($rule).Count | Should-Be 2
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
