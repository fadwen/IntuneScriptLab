#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    A finding about a tenant policy itself, kept or left out by the caller's rule selection.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }

    function script:Get-Finding {
        param([hashtable]$Selection = @{})
        InModuleScope IntuneScriptLab -Parameters @{ Selection = $Selection } {
            $findingSplat = @{
                PolicyKind = 'PlatformScript'; Policy = @{ id = 'p1'; displayName = 'Set-Wallpaper' }
                Rule = 'IslAssignmentIssue'; Severity = 'Warning'; Message = 'No assignment'
                Evidence = '(ASSIGN-NONE)'
            }
            @(ConvertTo-IslPolicyFinding @findingSplat @Selection)
        }
    }
}

Describe 'ConvertTo-IslPolicyFinding' -Tag 'Unit', 'Private' {

    It 'writes the finding with the role policy and no script position' {
        $findings = Get-Finding

        $findings | Should-BeCollection -Count 1
        $findings[0] | Should-HaveType 'IntuneScriptLab.DeploymentFinding'
        $findings[0].Role | Should-Be 'policy'
        $findings[0].PolicyName | Should-Be 'Set-Wallpaper'
        $findings[0].RuleName | Should-Be 'IslAssignmentIssue'
        $findings[0].Severity | Should-Be 'Warning'
        $findings[0].Message | Should-Be 'No assignment'
        $findings[0].Evidence | Should-Be '(ASSIGN-NONE)'
        $findings[0].Line | Should-Be 0
        $findings[0].ScriptType | Should-Be ''
    }

    It 'writes <Count> finding(s) for <Case>' -ForEach @(
        @{ Case = 'a matching -IncludeRule'; Selection = @{ IncludeRule = 'IslAssign*' }; Count = 1 }
        @{ Case = 'another -IncludeRule'; Selection = @{ IncludeRule = 'IslFilter*' }; Count = 0 }
        @{ Case = 'a matching -ExcludeRule'; Selection = @{ ExcludeRule = 'IslAssignmentIssue' }; Count = 0 }
        @{ Case = '-MinimumSeverity Warning'; Selection = @{ MinimumSeverity = 'Warning' }; Count = 1 }
        @{ Case = '-MinimumSeverity Error'; Selection = @{ MinimumSeverity = 'Error' }; Count = 0 }
    ) {
        Get-Finding -Selection $Selection | Should-BeCollection -Count $Count
    }
}
