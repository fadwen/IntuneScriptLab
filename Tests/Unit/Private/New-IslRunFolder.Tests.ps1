#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The folder a harness run copies its script into. A run as another account has it under
    ProgramData, where every local user may create folders and add files and a new folder inherits
    that; the module's two levels there get an access list of their own, and a level that someone
    else owns or that links elsewhere refuses the run. ProgramData is pointed at the test's own drive
    and given the write access the real one has.
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
        It 'makes the folder under ProgramData and grants the account that folder only' {
            $folder = InModuleScope IntuneScriptLab { New-IslRunFolder -Account 'isl-user' }

            $runs = Join-Path $env:ProgramData 'IntuneScriptLab\Runs'
            (Split-Path -Path $folder -Parent) | Should-Be $runs
            Test-Path -LiteralPath $folder -PathType Container | Should-BeTrue
            Should-Invoke Grant-IslFolderAccess -ModuleName IntuneScriptLab -Times 1 -Exactly -ParameterFilter {
                $Path -eq $folder -and $Account -eq 'isl-user'
            }
        }

        It 'closes <Level> to everyone but SYSTEM, the administrators and the caller' -ForEach @(
            @{ Level = 'IntuneScriptLab' }
            @{ Level = 'IntuneScriptLab\Runs' }
        ) {
            $null = InModuleScope IntuneScriptLab { New-IslRunFolder -Account 'isl-user' }

            $path = Join-Path $env:ProgramData $Level
            (Get-Acl -LiteralPath $path).AreAccessRulesProtected | Should-BeTrue
            $rules = @(Get-RuleSid -Path $path)
            $rules | Should-All { -not $_.Inherited }
            $sids = @($rules.Sid | Sort-Object -Unique)
            $sids | Should-BeCollection -Count 3
            $sids | Should-ContainCollection 'S-1-5-18'
            $sids | Should-ContainCollection 'S-1-5-32-544'
            $sids | Should-ContainCollection $script:CallerSid
        }

        It 'leaves the run folder nothing of the write access ProgramData gives every user' {
            # The same folder without the module's access list inherits Users' right to add files
            $plain = Join-Path $env:ProgramData 'plain\child'
            $null = New-Item -ItemType Directory -Path $plain
            @(Get-RuleSid -Path $plain).Sid | Should-ContainCollection $script:UsersSid

            $folder = InModuleScope IntuneScriptLab { New-IslRunFolder -Account 'isl-user' }
            @(Get-RuleSid -Path $folder).Sid | Should-NotContainCollection $script:UsersSid
        }

        It 'restricts a module folder that was there before it, with the write access inherited' {
            $existing = Join-Path $env:ProgramData 'IntuneScriptLab\Runs'
            $null = New-Item -ItemType Directory -Path $existing
            @(Get-RuleSid -Path $existing).Sid | Should-ContainCollection $script:UsersSid

            $null = InModuleScope IntuneScriptLab { New-IslRunFolder -Account 'isl-user' }
            @(Get-RuleSid -Path $existing).Sid | Should-NotContainCollection $script:UsersSid
        }
    }

    Context 'A module folder that cannot be trusted' {
        It 'refuses a module folder that is a link to another folder, and changes nothing there' {
            $elsewhere = Join-Path $TestDrive "elsewhere-$([guid]::NewGuid().ToString('N'))"
            $null = New-Item -ItemType Directory -Path $elsewhere
            $link = Join-Path $env:ProgramData 'IntuneScriptLab'
            $null = New-Item -ItemType Junction -Path $link -Value $elsewhere
            $before = (Get-Acl -LiteralPath $elsewhere).Sddl

            $failure = { InModuleScope IntuneScriptLab { New-IslRunFolder -Account 'isl-user' } } | Should-Throw
            $failure.FullyQualifiedErrorId | Should-BeLikeString 'RunFolderUnsafe,*'
            $failure.Exception.Message | Should-BeLikeString "*$link is a link to another folder*"
            (Get-Acl -LiteralPath $elsewhere).Sddl | Should-Be $before
            Should-Invoke Grant-IslFolderAccess -ModuleName IntuneScriptLab -Times 0 -Exactly
        }

        It 'refuses a module folder that another user owns' {
            # Another user's SID as the owner: a test cannot hand its folder to someone else
            Mock Get-Acl -ModuleName IntuneScriptLab {
                $acl = [pscustomobject]@{}
                $acl | Add-Member -MemberType ScriptMethod -Name GetOwner -Value {
                    param($type)
                    [System.Security.Principal.SecurityIdentifier]::new('S-1-5-21-1-2-3-1001')
                }
                $acl
            }

            $failure = { InModuleScope IntuneScriptLab { New-IslRunFolder -Account 'isl-user' } } | Should-Throw
            $failure.FullyQualifiedErrorId | Should-BeLikeString 'RunFolderUnsafe,*'
            $failure.Exception.Message | Should-BeLikeString '*is owned by S-1-5-21-1-2-3-1001*'
            Should-Invoke Grant-IslFolderAccess -ModuleName IntuneScriptLab -Times 0 -Exactly
        }

        It 'names the folder when icacls refuses to restrict it' {
            Mock Invoke-IslNativeCommand -ModuleName IntuneScriptLab {
                [pscustomobject]@{ ExitCode = 5; StdOut = ''; StdErr = 'Access is denied.' }
            }

            $failure = { InModuleScope IntuneScriptLab { New-IslRunFolder -Account 'isl-user' } } | Should-Throw
            $failure.FullyQualifiedErrorId | Should-BeLikeString 'RunFolderNotRestricted,*'
            $failure.Exception.Message | Should-BeLikeString '*IntuneScriptLab: Access is denied.*'
            Should-Invoke Grant-IslFolderAccess -ModuleName IntuneScriptLab -Times 0 -Exactly
        }
    }
}
