#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The result of comparing one script of a tenant policy with its local copy.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }
}

Describe 'ConvertTo-IslDriftResult' -Tag 'Unit', 'Private' {

    It 'names the policy and role, and leaves empty differences out' {
        $result = InModuleScope IntuneScriptLab {
            $resultSplat = @{
                PolicyKind = 'Remediation'
                Policy = @{ id = 'p1'; displayName = 'Fix-Widget'; lastModifiedDateTime = '2026-09-20T10:00:00Z' }
                Role = 'detection'; State = 'Drifted'; Differences = @('Bom', '', 'Settings'); Detail = 'differs'
                LocalPath = 'C:\s\detect.ps1'; LocalHash = 'aaaaaaaaaaaa'; TenantHash = 'bbbbbbbbbbbb'
            }
            ConvertTo-IslDriftResult @resultSplat
        }

        $result | Should-HaveType 'IntuneScriptLab.DriftResult'
        $result.Kind | Should-Be 'Remediation'
        $result.PolicyName | Should-Be 'Fix-Widget'
        $result.PolicyId | Should-Be 'p1'
        $result.Role | Should-Be 'detection'
        $result.State | Should-Be 'Drifted'
        $result.Differences | Should-BeCollection -Count 2
        $result.Differences[0] | Should-Be 'Bom'
        $result.Differences[1] | Should-Be 'Settings'
        $result.LocalPath | Should-Be 'C:\s\detect.ps1'
        $result.TenantModified | Should-Be '2026-09-20T10:00:00Z'
    }

    It 'takes a -Map entry without a policy, with no kind and the role policy' {
        $result = InModuleScope IntuneScriptLab {
            $orphan = [pscustomobject]@{ displayName = 'Gone'; id = ''; lastModifiedDateTime = $null }
            ConvertTo-IslDriftResult -Policy $orphan -Role 'policy' -State 'NotInTenant' -LocalPath 'gone.ps1'
        }

        $result.Kind | Should-Be ''
        $result.PolicyName | Should-Be 'Gone'
        $result.Differences | Should-BeCollection @()
    }
}
