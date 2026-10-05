#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The grant on the run folder another account's script is copied to. By SID where Windows can
    resolve the account, because the sign-in name of an Entra account is not a name icacls looks up
    (VM 125, 2026-10-05); by the name as given otherwise.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    $script:Me = [System.Security.Principal.WindowsIdentity]::GetCurrent()

    function Grant-Access {
        param([string]$Path, [string]$Account, [string]$Preference = 'Continue')
        $parameters = @{ Path = $Path; Account = $Account; Preference = $Preference }
        InModuleScope IntuneScriptLab -Parameters $parameters {
            # What a caller's -ErrorAction leaves in force inside the module
            $ErrorActionPreference = $Preference
            Grant-IslFolderAccess -Path $Path -Account $Account
        }
    }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Grant-IslFolderAccess' -Tag 'Unit', 'Private' {

    BeforeEach {
        $script:Folder = Join-Path $TestDrive "run-$([guid]::NewGuid().ToString('N'))"
        $null = New-Item -ItemType Directory -Path $script:Folder
    }

    It 'grants Modify, inherited by files and folders, by the SID of an account Windows resolves' {
        Mock Resolve-IslAccount -ModuleName IntuneScriptLab {
            [pscustomobject]@{ Name = 'AzureAD\IslVerylongdisplayna'; Sid = 'S-1-5-32-545' }
        }
        # S-1-5-32-545 is BUILTIN\Users, standing in for the account: the grant has to land on the
        # SID it was given, whatever the name passed in
        Grant-Access $script:Folder 'isl-verylongusername-test01@4nlnm3.onmicrosoft.com'
        $rule = (Get-Acl -Path $script:Folder).Access | Where-Object {
            -not $_.IsInherited -and
            $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value -eq 'S-1-5-32-545'
        }
        @($rule).Count | Should-Be 1
        "$($rule.FileSystemRights)" | Should-BeLikeString '*Modify*'
        "$($rule.InheritanceFlags)" | Should-Be 'ContainerInherit, ObjectInherit'
    }

    It 'grants by the name as given when Windows does not resolve it' {
        Mock Resolve-IslAccount -ModuleName IntuneScriptLab { }
        Grant-Access $script:Folder $script:Me.Name
        $rule = (Get-Acl -Path $script:Folder).Access | Where-Object {
            -not $_.IsInherited -and "$($_.IdentityReference)" -eq $script:Me.Name
        }
        @($rule).Count | Should-Be 1
    }

    It 'names the account and the folder when icacls refuses, under error action <Preference>' -ForEach @(
        @{ Preference = 'Continue' }
        @{ Preference = 'Stop' }
    ) {
        # Under Stop, Windows PowerShell 5.1 ended the function at icacls' first stderr line with
        # that line alone as the message (the CI runner and the lab device both showed it)
        Mock Resolve-IslAccount -ModuleName IntuneScriptLab { }
        $missing = "$env:COMPUTERNAME\no-such-account-for-isl"
        $failure = { Grant-Access $script:Folder $missing $Preference } | Should-Throw
        $failure.Exception.Message | Should-BeLikeString "Could not grant $missing access to *No mapping*"
    }
}
