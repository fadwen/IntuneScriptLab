#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The folder a harness run copies its script into. A run as another account has it directly
    under ProgramData, where every local user may create folders and add files and a new folder
    inherits that; the run folder is created with an access list of its own under a name new for
    each run, and anything already in its place, or a folder that comes out owned by someone else
    or inheriting, refuses the run. ProgramData is pointed at the test's own drive and given the
    write access the real one has.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }
    $script:CallerSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $script:UsersSid = 'S-1-5-32-545'

    function Get-RuleSid {
        <#
        .SYNOPSIS
            Gets the SID of each access rule on a folder.

        .DESCRIPTION
            Reads the folder's access list and returns the SID that each rule names, with whether
            the rule is inherited, so that a test can compare who may open the folder.

        .PARAMETER Path
            The folder.

        .EXAMPLE
            Get-RuleSid -Path $folder

            Lists the SIDs of the rules on the folder.

        .INPUTS
            None.

        .OUTPUTS
            IntuneScriptLab.Test.RuleSid. Sid and Inherited.
        #>
        [CmdletBinding()]
        [OutputType('IntuneScriptLab.Test.RuleSid')]
        param(
            [Parameter(Mandatory)]
            [string]$Path
        )

        foreach ($rule in (Get-Acl -LiteralPath $Path).Access) {
            [pscustomobject]@{
                PSTypeName = 'IntuneScriptLab.Test.RuleSid'
                Sid = $rule.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value
                Inherited = $rule.IsInherited
            }
        }
    }
}

Describe 'New-IslRunFolder' -Tag 'Unit', 'Private' {

    BeforeEach {
        $script:SavedProgramData = $env:ProgramData
        $env:ProgramData = Join-Path $TestDrive "programdata-$([guid]::NewGuid().ToString('N'))"
        $null = New-Item -ItemType Directory -Path $env:ProgramData
        # What the real ProgramData lets every local user do in the folders below it
        $icacls = Join-Path ([System.Environment]::SystemDirectory) 'icacls.exe'
        $null = & $icacls $env:ProgramData /grant "*$($script:UsersSid):(CI)(WD,AD)"
        Mock Grant-IslFolderAccess -ModuleName IntuneScriptLab { }
    }

    AfterEach {
        $env:ProgramData = $script:SavedProgramData
    }

    Context 'A run as the current user' {
        It 'makes a new folder under the caller''s temp folder and grants nothing' {
            $folder = InModuleScope IntuneScriptLab { New-IslRunFolder }
            try {
                $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'IntuneScriptLab'
                (Split-Path -Path $folder -Parent) | Should-Be $tempRoot
                Test-Path -LiteralPath $folder -PathType Container | Should-BeTrue
                Should-Invoke Grant-IslFolderAccess -ModuleName IntuneScriptLab -Times 0 -Exactly
            } finally {
                Remove-Item -LiteralPath $folder -Recurse -Force
            }
        }
    }

    Context 'A run as another account' {
        It 'makes a folder of its own directly under ProgramData and grants the account that folder' {
            $id = [guid]::NewGuid().ToString('N')
            $folder = InModuleScope IntuneScriptLab -Parameters @{ Id = $id } {
                New-IslRunFolder -Account 'isl-user' -RunId $Id
            }

            $folder | Should-Be (Join-Path $env:ProgramData "IntuneScriptLabRun-$id")
            Test-Path -LiteralPath $folder -PathType Container | Should-BeTrue
            Should-Invoke Grant-IslFolderAccess -ModuleName IntuneScriptLab -Times 1 -Exactly -ParameterFilter {
                $Path -eq $folder -and $Account -eq 'isl-user'
            }
        }

        It 'gives each run a new name, so that no other user can take the name first' {
            $first = InModuleScope IntuneScriptLab { New-IslRunFolder -Account 'isl-user' }
            $second = InModuleScope IntuneScriptLab { New-IslRunFolder -Account 'isl-user' }

            $second | Should-NotBe $first
            (Split-Path -Path $first -Leaf) | Should-BeLikeString 'IntuneScriptLabRun-*'
            (Split-Path -Path $second -Leaf) | Should-BeLikeString 'IntuneScriptLabRun-*'
        }

        It 'creates the folder closed to everyone but SYSTEM, the administrators and the caller' {
            $folder = InModuleScope IntuneScriptLab { New-IslRunFolder -Account 'isl-user' }

            (Get-Acl -LiteralPath $folder).AreAccessRulesProtected | Should-BeTrue
            $rules = @(Get-RuleSid -Path $folder)
            $rules | Should-All { -not $_.Inherited }
            $sids = @($rules.Sid | Sort-Object -Unique)
            $sids | Should-BeCollection -Count 3
            $sids | Should-ContainCollection 'S-1-5-18'
            $sids | Should-ContainCollection 'S-1-5-32-544'
            $sids | Should-ContainCollection $script:CallerSid
        }

        It 'leaves the run folder nothing of the write access ProgramData gives every user' {
            # A folder made there the plain way inherits Users' right to add files
            $plain = Join-Path $env:ProgramData 'plain'
            $null = New-Item -ItemType Directory -Path $plain
            @(Get-RuleSid -Path $plain).Sid | Should-ContainCollection $script:UsersSid

            $folder = InModuleScope IntuneScriptLab { New-IslRunFolder -Account 'isl-user' }
            @(Get-RuleSid -Path $folder).Sid | Should-NotContainCollection $script:UsersSid
        }
    }

    Context 'Something already in the run folder''s place' {
        It 'refuses a <Kind> under the name, and leaves it as it is' -ForEach @(
            @{ Kind = 'folder'; Problem = 'is already there' }
            @{ Kind = 'file'; Problem = 'is already there' }
            @{ Kind = 'link to another folder'; Problem = 'is already there' }
        ) {
            $id = [guid]::NewGuid().ToString('N')
            $path = Join-Path $env:ProgramData "IntuneScriptLabRun-$id"
            switch ($Kind) {
                'folder' { $null = New-Item -ItemType Directory -Path $path }
                'file' { $null = New-Item -ItemType File -Path $path }
                default {
                    $elsewhere = Join-Path $TestDrive "elsewhere-$id"
                    $null = New-Item -ItemType Directory -Path $elsewhere
                    $null = New-Item -ItemType Junction -Path $path -Value $elsewhere
                }
            }
            $before = (Get-Acl -LiteralPath $path).Sddl

            $failure = { InModuleScope IntuneScriptLab -Parameters @{ Id = $id } {
                    New-IslRunFolder -Account 'isl-user' -RunId $Id
                } } | Should-Throw
            $failure.FullyQualifiedErrorId | Should-BeLikeString 'RunFolderUnsafe,*'
            $failure.Exception.Message | Should-BeLikeString "*$path $Problem*"
            (Get-Acl -LiteralPath $path).Sddl | Should-Be $before
            Should-Invoke Grant-IslFolderAccess -ModuleName IntuneScriptLab -Times 0 -Exactly
        }

        It 'refuses a folder that came out <Case>' -ForEach @(
            @{ Case = 'owned by another user'; Owner = 'S-1-5-21-1-2-3-1001'; Protected = $true
                Problem = 'is owned by S-1-5-21-1-2-3-1001'
            }
            @{ Case = 'inheriting from ProgramData'; Owner = 'S-1-5-32-544'; Protected = $false
                Problem = 'inherits the access of ProgramData'
            }
        ) {
            # What another user would leave if they made the folder between the check and the
            # creation; a test cannot hand its folder to someone else, so the access list is faked
            Mock Get-Acl -ModuleName IntuneScriptLab -MockWith {
                $acl = [pscustomobject]@{ AreAccessRulesProtected = $Protected; Sid = $Owner }
                $acl | Add-Member -MemberType ScriptMethod -Name GetOwner -Value {
                    [System.Security.Principal.SecurityIdentifier]::new($this.Sid)
                }
                $acl
            }

            $failure = { InModuleScope IntuneScriptLab { New-IslRunFolder -Account 'isl-user' } } | Should-Throw
            $failure.FullyQualifiedErrorId | Should-BeLikeString 'RunFolderUnsafe,*'
            $failure.Exception.Message | Should-BeLikeString "*$Problem*"
            Should-Invoke Grant-IslFolderAccess -ModuleName IntuneScriptLab -Times 0 -Exactly
        }
    }
}