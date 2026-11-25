#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    A finding about a deployed script, named after its tenant policy.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }
}

Describe 'ConvertTo-IslDeploymentFinding' -Tag 'Unit', 'Private' {

    It 'adds the policy kind, name, id and role to the finding' {
        $result = InModuleScope IntuneScriptLab {
            $finding = [pscustomobject]@{
                RuleName = 'IslInteractiveCall'; Severity = 'Error'; Message = 'Read-Host waits'
                ScriptType = 'Detection'; Line = 3; Column = 1; Text = 'Read-Host'; Evidence = '(PS-PROBE-ARGS)'
            }
            $policy = @{ id = 'p1'; displayName = 'Detect-Printer' }
            $findingSplat = @{
                PolicyKind = 'Remediation'; Policy = $policy; Role = 'detection'; Finding = $finding
            }
            ConvertTo-IslDeploymentFinding @findingSplat
        }

        $result | Should-HaveType 'IntuneScriptLab.DeploymentFinding'
        $result.Kind | Should-Be 'Remediation'
        $result.PolicyName | Should-Be 'Detect-Printer'
        $result.PolicyId | Should-Be 'p1'
        $result.Role | Should-Be 'detection'
        $result.RuleName | Should-Be 'IslInteractiveCall'
        $result.Severity | Should-Be 'Error'
        $result.Line | Should-Be 3
        $result.Text | Should-Be 'Read-Host'
        $result.Evidence | Should-Be '(PS-PROBE-ARGS)'
    }
}
