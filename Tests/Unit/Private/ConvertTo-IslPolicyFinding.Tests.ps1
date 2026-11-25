#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    A finding about a tenant policy itself, kept or left out by the caller's rule selection.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    function script:Get-Finding {
        <#
        .SYNOPSIS
            Gets the findings that ConvertTo-IslPolicyFinding makes of one fixed finding.

        .DESCRIPTION
            Calls the private function inside the module with a warning-level assignment finding
            for a platform script, and with the given selection parameters, so that each test
            varies only the selection.

        .PARAMETER Selection
            Further parameters of ConvertTo-IslPolicyFinding: IncludeRule, ExcludeRule or
            MinimumSeverity.

        .EXAMPLE
            Get-Finding -Selection @{ ExcludeRule = 'IslAssignmentIssue' }

            Returns what is left of the finding once its rule is excluded.

        .INPUTS
            None.

        .OUTPUTS
            IntuneScriptLab.DeploymentFinding. The findings that pass the selection.
        #>
        [CmdletBinding()]
        [OutputType('IntuneScriptLab.DeploymentFinding')]
        param(
            [hashtable]$Selection = @{}
        )

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
