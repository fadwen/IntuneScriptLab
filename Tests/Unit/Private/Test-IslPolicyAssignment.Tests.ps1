#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The assignments of a tenant policy: none, a run-once schedule that has passed, and a
    user-context script assigned to devices. Group counts come from the mocked Graph seam.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    function script:New-Target {
        <#
        .SYNOPSIS
            Builds the target of an assignment as a Graph reply holds it.

        .DESCRIPTION
            Returns a hashtable with the OData type of the target and, when a group id is given,
            the group it names.

        .PARAMETER Type
            The type of the target without its #microsoft.graph. prefix, such as
            groupAssignmentTarget.

        .PARAMETER GroupId
            The id of the group the target names. Left out, the target has no groupId.

        .EXAMPLE
            New-Target -Type 'groupAssignmentTarget' -GroupId 'g-devices'

            Returns the target of an assignment to the group g-devices.

        .INPUTS
            None.

        .OUTPUTS
            System.Collections.Hashtable. The target.
        #>
        [CmdletBinding()]
        [OutputType([hashtable])]
        param(
            [string]$Type,

            [string]$GroupId
        )

        $target = @{ '@odata.type' = "#microsoft.graph.$Type" }
        if ($GroupId) { $target['groupId'] = $GroupId }
        $target
    }

    function script:Get-AssignmentFinding {
        <#
        .SYNOPSIS
            Gets the findings of Test-IslPolicyAssignment for a remediation's assignments.

        .DESCRIPTION
            Builds a remediation with the given assignments and an empty group cache, and calls the
            private function inside the module. Extra replaces or adds parameters, so that each
            test names only what it is about.

        .PARAMETER Assignments
            The assignments of the policy, each a hashtable with a target.

        .PARAMETER RunAsAccount
            The account the remediation runs as, system by default.

        .PARAMETER Extra
            Parameters of Test-IslPolicyAssignment that replace or add to the defaults.

        .EXAMPLE
            Get-AssignmentFinding -Assignments @(@{ target = $target }) -RunAsAccount 'user'

            Returns the findings for a remediation that runs as the user and has one assignment.

        .INPUTS
            None.

        .OUTPUTS
            IntuneScriptLab.DeploymentFinding. What Test-IslPolicyAssignment returns.
        #>
        [CmdletBinding()]
        [OutputType('IntuneScriptLab.DeploymentFinding')]
        param(
            [object[]]$Assignments,

            [string]$RunAsAccount = 'system',

            [hashtable]$Extra = @{}
        )

        $parameters = @{
            PolicyKind = 'Remediation'
            Policy = @{ id = 'p1'; displayName = 'Detect'; assignments = $Assignments }
            RunAsAccount = $RunAsAccount
            GroupState = @{ Cache = @{}; Blocked = $false }
        }
        foreach ($key in $Extra.Keys) { $parameters[$key] = $Extra[$key] }
        InModuleScope IntuneScriptLab -Parameters @{ Parameters = $parameters } {
            @(Test-IslPolicyAssignment @Parameters)
        }
    }
}

Describe 'Test-IslPolicyAssignment' -Tag 'Unit', 'Private' {

    BeforeAll {
        # Group g-devices holds two devices
        Mock Invoke-IslGraphRequest -ModuleName IntuneScriptLab { '2' }
    }

    Context 'Assignments that reach nobody' {
        It 'warns about <Case>' -ForEach @(
            @{ Case = 'no assignment'; Assignments = @(); What = 'No assignment' }
            @{
                Case = 'exclusions only'; What = 'Only exclusion assignments'
                Assignments = @(@{
                        target = @{
                            '@odata.type' = '#microsoft.graph.exclusionGroupAssignmentTarget'; groupId = 'g1'
                        }
                    })
            }
        ) {
            $findings = Get-AssignmentFinding -Assignments $Assignments

            $findings | Should-BeCollection -Count 1
            $findings[0].RuleName | Should-Be 'IslAssignmentIssue'
            $findings[0].Severity | Should-Be 'Warning'
            $findings[0].Message | Should-BeLikeString "${What}: no device resolves the policy*"
        }
    }

    Context 'Run-once schedules' {
        It 'notes a run-once schedule whose time has passed, in <Zone>' -ForEach @(
            @{ UseUtc = $true; Zone = 'UTC' }
            @{ UseUtc = $false; Zone = 'device local time' }
        ) {
            $schedule = @{
                '@odata.type' = '#microsoft.graph.deviceHealthScriptRunOnceSchedule'
                date = '2020-01-15'; time = '08:30:00'; useUtc = $UseUtc
            }
            $assignment = @{ target = (New-Target -Type 'allDevicesAssignmentTarget'); runSchedule = $schedule }
            $findings = Get-AssignmentFinding -Assignments @($assignment)

            $findings | Should-BeCollection -Count 1
            $findings[0].RuleName | Should-Be 'IslScheduleIssue'
            $findings[0].Message | Should-Be ("Run-once schedule at 2020-01-15 08:30:00 ($Zone) has passed: a " +
                'device that already ran it will not again, and one that fetches the policy now runs it ' +
                'once at the fetch')
        }

        It 'notes nothing for a run-once schedule still to come, or a daily one' {
            $future = @{
                '@odata.type' = '#microsoft.graph.deviceHealthScriptRunOnceSchedule'
                date = '2099-01-15'; time = '08:30:00'; useUtc = $true
            }
            $daily = @{ '@odata.type' = '#microsoft.graph.deviceHealthScriptDailySchedule'; interval = 1 }
            $assignments = @(
                @{ target = (New-Target -Type 'allDevicesAssignmentTarget'); runSchedule = $future }
                @{ target = (New-Target -Type 'allLicensedUsersAssignmentTarget'); runSchedule = $daily }
            )

            Get-AssignmentFinding -Assignments $assignments | Should-BeCollection @()
        }
    }

    Context 'User context assigned to devices' {
        It 'notes a user-context script assigned to all devices and to a group of devices' {
            $assignments = @(
                @{ target = (New-Target -Type 'allDevicesAssignmentTarget') }
                @{ target = (New-Target -Type 'groupAssignmentTarget' -GroupId 'g-devices') }
            )
            $findings = Get-AssignmentFinding -Assignments $assignments -RunAsAccount 'user'

            $findings | Should-BeCollection -Count 1
            $findings[0].Severity | Should-Be 'Information'
            $expected = 'User context, assigned to devices (all devices, g-devices)*'
            $findings[0].Message | Should-BeLikeString $expected
        }

        It 'notes nothing for <Case>' -ForEach @(
            @{ Case = 'a system-context script'; RunAsAccount = 'system'; Extra = @{} }
            @{
                Case = 'a user-context script under -SkipGroupLookup'; RunAsAccount = 'user'
                Extra = @{ SkipGroupLookup = $true }
            }
        ) {
            $assignments = @(@{ target = (New-Target -Type 'groupAssignmentTarget' -GroupId 'g-devices') })

            $findings = Get-AssignmentFinding -Assignments $assignments -RunAsAccount $RunAsAccount -Extra $Extra
            $findings | Should-BeCollection @()
        }
    }

    Context 'Rule selection' {
        It 'applies the caller''s -ExcludeRule' {
            $findings = Get-AssignmentFinding -Assignments @() -Extra @{ ExcludeRule = 'IslAssignmentIssue' }
            $findings | Should-BeCollection @()
        }
    }
}
