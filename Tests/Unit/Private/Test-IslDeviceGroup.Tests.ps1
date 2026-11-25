#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Whether every member of an Entra group is a device, asked of the mocked Graph seam once for
    each group.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }

    # Members and devices among them, by group; $count answers with the number as text
    $script:Groups = @{
        devices = @{ Members = 3; Devices = 3 }
        mixed = @{ Members = 25; Devices = 20 }
        empty = @{ Members = 0; Devices = 0 }
    }

    function script:Test-Group {
        param([string]$GroupId, [hashtable]$State, [switch]$SkipGroupLookup)
        $scope = @{ GroupId = $GroupId; State = $State; Skip = $SkipGroupLookup }
        InModuleScope IntuneScriptLab -Parameters $scope {
            Test-IslDeviceGroup -GroupId $GroupId -State $State -SkipGroupLookup:$Skip
        }
    }
}

Describe 'Test-IslDeviceGroup' -Tag 'Unit', 'Private' {

    BeforeAll {
        Mock Invoke-IslGraphRequest -ModuleName IntuneScriptLab {
            $countPattern = '^/v1\.0/groups/([^/]+)/members(/microsoft\.graph\.device)?/\$count$'
            if ($Uri -notmatch $countPattern) { throw "unexpected $Uri" }
            $group = $script:Groups[$Matches[1]]
            if ($Matches[2]) { "$($group.Devices)" } else { "$($group.Members)" }
        }
    }

    Context 'Core Functionality' {
        It 'gives <Expected> for the group <GroupId>' -ForEach @(
            @{ GroupId = 'devices'; Expected = $true }
            @{ GroupId = 'mixed'; Expected = $false }
            @{ GroupId = 'empty'; Expected = $false }
        ) {
            Test-Group -GroupId $GroupId -State @{ Cache = @{}; Blocked = $false } | Should-Be $Expected
        }

        It 'asks for both counts with the eventual consistency header' {
            $null = Test-Group -GroupId 'devices' -State @{ Cache = @{}; Blocked = $false }

            Should-Invoke Invoke-IslGraphRequest -ModuleName IntuneScriptLab -Times 2 -Exactly -ParameterFilter {
                $Headers['ConsistencyLevel'] -eq 'eventual'
            }
        }

        It 'asks once for each group in the run' {
            $state = @{ Cache = @{}; Blocked = $false }
            $first = Test-Group -GroupId 'devices' -State $state
            $second = Test-Group -GroupId 'devices' -State $state

            $first | Should-BeTrue
            $second | Should-BeTrue
            Should-Invoke Invoke-IslGraphRequest -ModuleName IntuneScriptLab -Times 2 -Exactly
        }

        It 'asks nothing under -SkipGroupLookup, and counts no group as a device group' {
            Test-Group -GroupId 'devices' -State @{ Cache = @{}; Blocked = $false } -SkipGroupLookup |
                Should-BeFalse
            Should-Invoke Invoke-IslGraphRequest -ModuleName IntuneScriptLab -Times 0 -Exactly
        }
    }

    Context 'Error Handling' {
        It 'warns once, and asks nothing more, when the members cannot be read' {
            Mock Invoke-IslGraphRequest -ModuleName IntuneScriptLab { throw 'Insufficient privileges' }
            $state = @{ Cache = @{}; Blocked = $false }

            $output = @(Test-Group -GroupId 'devices' -State $state 3>&1)
            $later = Test-Group -GroupId 'mixed' -State $state 3>$null

            $warnings = @($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
            $warnings | Should-BeCollection -Count 1
            $warnings[0].Message | Should-BeLikeString '*Insufficient privileges*GroupMember.Read.All*'
            $state['Blocked'] | Should-BeTrue
            $later | Should-BeFalse
            Should-Invoke Invoke-IslGraphRequest -ModuleName IntuneScriptLab -Times 1 -Exactly
        }
    }
}
