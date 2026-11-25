#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The health line of one deployed script policy, from its findings, drift, assignments and
    device counts.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }

    # The report of a policy assigned to one group, with what the case adds
    function script:Get-Report {
        param([hashtable]$Extra = @{}, [object[]]$Assignments)
        $assigned = @(@{ target = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget' } })
        if ($PSBoundParameters.ContainsKey('Assignments')) { $assigned = $Assignments }
        $parameters = @{
            PolicyKind = 'Remediation'
            Policy = @{
                id = 'p1'; displayName = 'Detect-Printer'; lastModifiedDateTime = '2026-11-01'
                assignments = $assigned
            }
            Context = 'system'
            FindingsByPolicy = @{}
        }
        foreach ($key in $Extra.Keys) { $parameters[$key] = $Extra[$key] }
        InModuleScope IntuneScriptLab -Parameters @{ Parameters = $parameters } {
            ConvertTo-IslHealthReport @Parameters
        }
    }
}

Describe 'ConvertTo-IslHealthReport' -Tag 'Unit', 'Private' {

    Context 'Core Functionality' {
        It 'reports a policy that is assigned, without findings or run state, as Healthy' {
            $report = Get-Report

            $report | Should-HaveType 'IntuneScriptLab.HealthReport'
            $report.Kind | Should-Be 'Remediation'
            $report.PolicyName | Should-Be 'Detect-Printer'
            $report.PolicyId | Should-Be 'p1'
            $report.Context | Should-Be 'system'
            $report.Assigned | Should-Be '1 include'
            $report.LastModified | Should-Be '2026-11-01'
            $report.Drift | Should-Be ''
            $report.Health | Should-Be 'Healthy'
            $report.Notes | Should-Be ''
        }

        It 'gives <Health> with the note <Note> for <Case>' -ForEach @(
            @{
                Case = 'an error finding'; Health = 'Broken'; Note = '1 error finding(s)'
                Extra = @{ FindingsByPolicy = @{ p1 = @([pscustomobject]@{ Severity = 'Error' }) } }
            }
            @{
                Case = 'a warning finding'; Health = 'Attention'; Note = '1 warning finding(s)'
                Extra = @{ FindingsByPolicy = @{ p1 = @([pscustomobject]@{ Severity = 'Warning' }) } }
            }
            @{
                Case = 'every device failing'; Health = 'Broken'; Note = 'every device that ran it failed'
                Extra = @{ Failed = 3; HasRunState = $true }
            }
            @{
                Case = 'some devices failing'; Health = 'Attention'; Note = '2 device(s) failed'
                Extra = @{ Succeeded = 5; Failed = 2; HasRunState = $true }
            }
            @{
                Case = 'devices still detecting'; Health = 'Attention'; Note = '4 device(s) still detect the issue'
                Extra = @{ Succeeded = 1; Detected = 4; HasRunState = $true }
            }
            @{
                Case = 'no device reporting'; Health = 'Attention'; Note = 'no device has reported yet'
                Extra = @{ HasRunState = $true }
            }
            @{
                Case = 'a device note'; Health = 'Attention'; Note = '2 device(s) not applicable'
                Extra = @{ DeviceNotes = @('2 device(s) not applicable', '') }
            }
        ) {
            $report = Get-Report -Extra $Extra

            $report.Health | Should-Be $Health
            $report.Notes | Should-Be $Note
        }

        It 'reports a policy assigned to nobody as Broken, even with only exclusions' {
            $exclusion = @{ target = @{ '@odata.type' = '#microsoft.graph.exclusionGroupAssignmentTarget' } }
            $report = Get-Report -Assignments @($exclusion)

            $report.Health | Should-Be 'Broken'
            $report.Notes | Should-Be 'assigned to nobody'
        }

        It 'gives the worst drift <Drift> for the states <States>' -ForEach @(
            @{ States = @('InSync', 'Drifted', 'Missing'); Drift = 'Drifted' }
            @{ States = @('Missing', 'Ambiguous'); Drift = 'Ambiguous' }
            @{ States = @('InSync', 'Missing'); Drift = 'Missing' }
            @{ States = @('NotInTenant'); Drift = 'NotInTenant' }
            @{ States = @('InSync', 'InSync'); Drift = 'InSync' }
        ) {
            $results = @(foreach ($state in $States) {
                    [pscustomobject]@{ Role = 'Detection'; State = $state; Detail = '' }
                })
            $report = Get-Report -Extra @{ DriftByPolicy = @{ p1 = $results } }

            $report.Drift | Should-Be $Drift
        }

        It 'gives NoScript when the caller compared and no script matched the policy' {
            (Get-Report -Extra @{ DriftByPolicy = @{} }).Drift | Should-Be 'NoScript'
        }

        It 'lists the scripts that are not in sync, with their detail' {
            $results = @(
                [pscustomobject]@{ Role = 'Detection'; State = 'InSync'; Detail = '' }
                [pscustomobject]@{ Role = 'Remediation'; State = 'Drifted'; Detail = 'line 4' }
            )
            $report = Get-Report -Extra @{ DriftByPolicy = @{ p1 = $results } }

            $report.DriftDetail | Should-Be 'Remediation: Drifted (line 4)'
            $report.Health | Should-Be 'Attention'
            $report.Notes | Should-Be 'drift: Drifted'
        }
    }
}
