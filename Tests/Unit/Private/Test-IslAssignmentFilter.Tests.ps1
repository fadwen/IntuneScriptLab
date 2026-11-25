#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The assignment filters on a tenant policy's assignments, read from the mocked Graph seam.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    $script:Filters = @{
        x64 = @{ id = 'x64'; displayName = 'x64 only'; rule = '(device.cpuArchitecture -eq "x64")' }
        quoted = @{ id = 'quoted'; displayName = 'Quoted'; rule = "(device.deviceName -eq 'X')" }
        fine = @{ id = 'fine'; displayName = 'Lab'; rule = '(device.deviceName -startsWith "LAB-")' }
    }

    # The findings for one policy whose single assignment carries the filter and type given
    function script:Test-Filter {
        <#
        .SYNOPSIS
            Runs Test-IslAssignmentFilter for a remediation with one group assignment.

        .DESCRIPTION
            Builds a remediation assigned to the group g1, with the given assignment filter when an
            id is given, and an empty filter cache, and calls the private function inside the
            module. Extra replaces or adds parameters, so that each test names only what it is about.

        .PARAMETER FilterId
            The id of the assignment filter. Left out, the assignment has no filter.

        .PARAMETER FilterType
            The filter type of the assignment, include by default.

        .PARAMETER Extra
            Parameters of Test-IslAssignmentFilter that replace or add to the defaults.

        .EXAMPLE
            Test-Filter -FilterId 'quoted' -Extra @{ MinimumSeverity = 'Warning' }

            Returns the findings of at least Warning for the assignment with the filter quoted.

        .INPUTS
            None.

        .OUTPUTS
            IntuneScriptLab.DeploymentFinding. What Test-IslAssignmentFilter returns.
        #>
        [CmdletBinding()]
        [OutputType('IntuneScriptLab.DeploymentFinding')]
        param(
            [string]$FilterId,

            [string]$FilterType = 'include',

            [hashtable]$Extra = @{}
        )

        $target = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = 'g1' }
        if ($FilterId) {
            $target['deviceAndAppManagementAssignmentFilterId'] = $FilterId
            $target['deviceAndAppManagementAssignmentFilterType'] = $FilterType
        }
        $parameters = @{
            PolicyKind = 'Remediation'
            Policy = @{ id = 'p1'; displayName = 'Detect'; assignments = @(@{ target = $target }) }
            FilterState = @{ Cache = @{}; Blocked = $false }
        }
        foreach ($key in $Extra.Keys) { $parameters[$key] = $Extra[$key] }
        InModuleScope IntuneScriptLab -Parameters @{ Parameters = $parameters } {
            @(Test-IslAssignmentFilter @Parameters)
        }
    }
}

Describe 'Test-IslAssignmentFilter' -Tag 'Unit', 'Private' {

    BeforeAll {
        Mock Invoke-IslGraphRequest -ModuleName IntuneScriptLab {
            $script:Filters[($Uri -split '/')[-1]]
        }
    }

    It 'warns about a clause no Windows device matches, naming the filter and its rule' {
        $findings = Test-Filter -FilterId 'x64'

        $findings | Should-BeCollection -Count 1
        $findings[0] | Should-HaveType 'IntuneScriptLab.DeploymentFinding'
        $findings[0].RuleName | Should-Be 'IslFilterIssue'
        $findings[0].Severity | Should-Be 'Warning'
        $findings[0].Role | Should-Be 'policy'
        $expected = "Filter 'x64 only' (include):*Rule: (device.cpuArchitecture -eq `"x64`")"
        $findings[0].Message | Should-BeLikeString $expected
        $findings[0].Evidence | Should-BeLikeString '*(FLT-V25, FLT-E07, FLT-V27, FLT-F01)'
    }

    It 'notes a rule the evaluator cannot read, with the reason' {
        $findings = Test-Filter -FilterId 'quoted'

        $findings | Should-BeCollection -Count 1
        $findings[0].Severity | Should-Be 'Information'
        $findings[0].Message | Should-BeLikeString "Filter 'Quoted' (include) uses syntax*does not read*"
    }

    It 'gives nothing for <Case>' -ForEach @(
        @{ Case = 'an assignment without a filter'; FilterId = ''; FilterType = 'include' }
        @{ Case = 'a filter type of none'; FilterId = 'x64'; FilterType = 'none' }
        @{ Case = 'a filter whose rule matches devices'; FilterId = 'fine'; FilterType = 'include' }
    ) {
        Test-Filter -FilterId $FilterId -FilterType $FilterType | Should-BeCollection @()
    }

    It 'applies the caller''s minimum severity' {
        Test-Filter -FilterId 'quoted' -Extra @{ MinimumSeverity = 'Warning' } | Should-BeCollection @()
    }
}
