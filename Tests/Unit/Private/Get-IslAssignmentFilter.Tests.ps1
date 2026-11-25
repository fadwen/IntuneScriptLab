#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    An assignment filter read from the mocked Graph seam once for each filter.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }

    function script:Get-Filter {
        param([string]$FilterId, [hashtable]$State)
        InModuleScope IntuneScriptLab -Parameters @{ FilterId = $FilterId; State = $State } {
            @(Get-IslAssignmentFilter -FilterId $FilterId -State $State)
        }
    }
}

Describe 'Get-IslAssignmentFilter' -Tag 'Unit', 'Private' {

    Context 'Core Functionality' {
        BeforeAll {
            Mock Invoke-IslGraphRequest -ModuleName IntuneScriptLab {
                @{ id = 'f1'; displayName = 'x64 only'; rule = '(device.cpuArchitecture -eq "x64")' }
            }
        }

        It 'reads the filter once for each id in the run' {
            $state = @{ Cache = @{}; Blocked = $false }
            $first = @(Get-Filter -FilterId 'f1' -State $state)
            $second = @(Get-Filter -FilterId 'f1' -State $state)

            $first | Should-BeCollection -Count 1
            $first[0]['displayName'] | Should-Be 'x64 only'
            $second | Should-BeCollection -Count 1
            Should-Invoke Invoke-IslGraphRequest -ModuleName IntuneScriptLab -Times 1 -Exactly -ParameterFilter {
                $Uri -eq '/beta/deviceManagement/assignmentFilters/f1'
            }
        }
    }

    Context 'Error Handling' {
        It 'warns once, gives nothing and asks nothing more when the filters cannot be read' {
            Mock Invoke-IslGraphRequest -ModuleName IntuneScriptLab { throw 'Forbidden' }
            $state = @{ Cache = @{}; Blocked = $false }

            $output = @(Get-Filter -FilterId 'f1' -State $state 3>&1)

            $output | Should-BeCollection -Count 1
            $output[0] | Should-HaveType ([System.Management.Automation.WarningRecord])
            $output[0].Message | Should-BeLikeString '*Forbidden*DeviceManagementConfiguration.Read.All*'
            $state['Blocked'] | Should-BeTrue
            Get-Filter -FilterId 'f2' -State $state 3>$null | Should-BeCollection @()
            Should-Invoke Invoke-IslGraphRequest -ModuleName IntuneScriptLab -Times 1 -Exactly
        }
    }
}
