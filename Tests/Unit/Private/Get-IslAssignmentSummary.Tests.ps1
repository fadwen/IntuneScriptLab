#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The assignments of a tenant policy summed up as a short text.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }

    # An assignment as Graph returns it, a dictionary
    function script:New-Assignment {
        param([string]$Type, [string]$FilterType)
        $target = @{ '@odata.type' = "#microsoft.graph.$Type" }
        if ($FilterType) {
            $target['deviceAndAppManagementAssignmentFilterId'] = 'filter-1'
            $target['deviceAndAppManagementAssignmentFilterType'] = $FilterType
        }
        @{ target = $target }
    }

    function script:Get-Summary {
        param([object[]]$Assignment)
        InModuleScope IntuneScriptLab -Parameters @{ Assignment = $Assignment } {
            Get-IslAssignmentSummary -Policy @{ id = 'p'; assignments = $Assignment }
        }
    }
}

Describe 'Get-IslAssignmentSummary' -Tag 'Unit', 'Private' {

    It 'counts includes, names all devices and all users, and counts exclusions and filters' {
        $summary = Get-Summary -Assignment @(
            (New-Assignment -Type 'allDevicesAssignmentTarget' -FilterType 'include')
            (New-Assignment -Type 'allLicensedUsersAssignmentTarget')
            (New-Assignment -Type 'groupAssignmentTarget' -FilterType 'none')
            (New-Assignment -Type 'exclusionGroupAssignmentTarget')
        )

        $summary | Should-HaveType 'IntuneScriptLab.AssignmentSummary'
        $summary.Text | Should-Be '3 include (all devices, all users), 1 exclusion, 1 filtered'
        $summary.Includes | Should-Be 3
    }

    It 'gives 0 include for a policy without assignments' {
        $summary = InModuleScope IntuneScriptLab { Get-IslAssignmentSummary -Policy @{ id = 'p' } }

        $summary.Text | Should-Be '0 include'
        $summary.Includes | Should-Be 0
    }

    It 'reads a policy that is an object, as a recorded fixture is' {
        $summary = InModuleScope IntuneScriptLab {
            $json = '{ "id": "p", "assignments": [ { "target": ' +
                '{ "@odata.type": "#microsoft.graph.groupAssignmentTarget" } } ] }'
            Get-IslAssignmentSummary -Policy ($json | ConvertFrom-Json)
        }

        $summary.Text | Should-Be '1 include'
    }
}
