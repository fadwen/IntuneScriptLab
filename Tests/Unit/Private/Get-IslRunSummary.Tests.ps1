#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The run summary of a remediation or platform script, read through the mocked Graph seam.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }

    $script:SummaryUri = '/beta/deviceManagement/deviceManagementScripts/s1/runSummary'
}

Describe 'Get-IslRunSummary' -Tag 'Unit', 'Private' {

    It 'gives the summary Graph returns' {
        Mock Invoke-IslGraphRequest -ModuleName IntuneScriptLab {
            @{ successDeviceCount = 4; errorDeviceCount = 1 }
        }

        $summary = InModuleScope IntuneScriptLab -Parameters @{ Uri = $script:SummaryUri } {
            Get-IslRunSummary -Uri $Uri
        }

        $summary['successDeviceCount'] | Should-Be 4
        Should-Invoke Invoke-IslGraphRequest -ModuleName IntuneScriptLab -Times 1 -Exactly -ParameterFilter {
            $Uri -eq '/beta/deviceManagement/deviceManagementScripts/s1/runSummary'
        }
    }

    It 'warns and gives nothing when the summary cannot be read' {
        Mock Invoke-IslGraphRequest -ModuleName IntuneScriptLab { throw 'Not found' }

        $output = @(InModuleScope IntuneScriptLab -Parameters @{ Uri = $script:SummaryUri } {
                Get-IslRunSummary -Uri $Uri 3>&1
            })

        $output | Should-BeCollection -Count 1
        $output[0] | Should-HaveType ([System.Management.Automation.WarningRecord])
        $output[0].Message | Should-BeLikeString 'Run summary could not be read from */s1/runSummary (Not found)'
    }
}
