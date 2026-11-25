#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The assignments of a tenant policy summed up as a short text.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    # An assignment as Graph returns it, a dictionary
    function script:New-Assignment {
        <#
        .SYNOPSIS
            Builds an assignment of a tenant policy with a target of the given type.

        .DESCRIPTION
            Returns a hashtable shaped like an assignment in a Graph reply. When a filter type is
            given, the target also carries the filter id filter-1 and that filter type.

        .PARAMETER Type
            The type of the target without its #microsoft.graph. prefix, such as
            groupAssignmentTarget.

        .PARAMETER FilterType
            The filter type of the target, such as include or none. Left out, the target has no
            filter.

        .EXAMPLE
            New-Assignment -Type 'allDevicesAssignmentTarget' -FilterType 'include'

            Returns an assignment to all devices with an include filter.

        .INPUTS
            None.

        .OUTPUTS
            System.Collections.Hashtable. The assignment, with its target.
        #>
        [CmdletBinding()]
        [OutputType([hashtable])]
        param(
            [string]$Type,

            [string]$FilterType
        )

        $target = @{ '@odata.type' = "#microsoft.graph.$Type" }
        if ($FilterType) {
            $target['deviceAndAppManagementAssignmentFilterId'] = 'filter-1'
            $target['deviceAndAppManagementAssignmentFilterType'] = $FilterType
        }
        @{ target = $target }
    }

    function script:Get-Summary {
        <#
        .SYNOPSIS
            Gets the summary Get-IslAssignmentSummary gives for a set of assignments.

        .DESCRIPTION
            Wraps the assignments in a policy with the id p and calls the private function inside
            the module with it.

        .PARAMETER Assignment
            The assignments of the policy, as New-Assignment returns them.

        .EXAMPLE
            Get-Summary -Assignment @(New-Assignment -Type 'allDevicesAssignmentTarget')

            Returns the summary of a policy assigned to all devices.

        .INPUTS
            None.

        .OUTPUTS
            IntuneScriptLab.AssignmentSummary. What Get-IslAssignmentSummary returns.
        #>
        [CmdletBinding()]
        [OutputType('IntuneScriptLab.AssignmentSummary')]
        param(
            [object[]]$Assignment
        )

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
