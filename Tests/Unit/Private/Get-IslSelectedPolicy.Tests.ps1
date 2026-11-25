#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The policies of one Graph list that the caller's -Name and -Id select. Graph is mocked at the
    Invoke-IslGraphRequest seam.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }

    function script:Get-Selected {
        param([hashtable]$Selection)
        InModuleScope IntuneScriptLab -Parameters @{ Selection = $Selection } {
            @(Get-IslSelectedPolicy -Uri '/beta/deviceManagement/deviceManagementScripts' @Selection)
        }
    }
}

Describe 'Get-IslSelectedPolicy' -Tag 'Unit', 'Private' {

    BeforeAll {
        Mock Invoke-IslGraphRequest -ModuleName IntuneScriptLab {
            @{ id = 'a'; displayName = 'Detect-Printer' }
            @{ id = 'b'; displayName = 'Detect-Disk' }
            @{ id = 'c'; displayName = 'Fix-Printer' }
        }
    }

    Context 'Core Functionality' {
        It 'reads every page of the list once' {
            $null = Get-Selected -Selection @{}

            $listed = { $Uri -eq '/beta/deviceManagement/deviceManagementScripts' -and $All }
            $invoked = @{
                CommandName = 'Invoke-IslGraphRequest'; ModuleName = 'IntuneScriptLab'; ParameterFilter = $listed
            }
            Should-Invoke @invoked -Times 1 -Exactly
        }

        It 'keeps the policies whose names match, in the order of the list' {
            $policies = @(Get-Selected -Selection @{ Name = 'Detect-*'; NameGiven = $true })

            $policies | Should-BeCollection -Count 2
            $policies[0]['id'] | Should-Be 'a'
            $policies[1]['id'] | Should-Be 'b'
        }

        It 'keeps the policy that -Id names when -Name is not given' {
            $policies = @(Get-Selected -Selection @{ Id = 'c' })

            $policies | Should-BeCollection -Count 1
            $policies[0]['displayName'] | Should-Be 'Fix-Printer'
        }

        It 'gives nothing when no policy is selected' {
            Get-Selected -Selection @{ Name = 'Remediate-*'; NameGiven = $true } | Should-BeCollection @()
        }
    }

    Context 'Error Handling' {
        It 'ends with the error of a list that cannot be read' {
            Mock Invoke-IslGraphRequest -ModuleName IntuneScriptLab {
                $record = [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new('Forbidden'), 'GraphForbidden',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)
                throw $record
            }

            { Get-Selected -Selection @{} } |
                Should-Throw -FullyQualifiedErrorId 'GraphForbidden*' -ExceptionMessage 'Forbidden'
        }
    }
}
