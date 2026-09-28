#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Where a Suppress directive reaches: the whole file from the header, the next code line from
    a line of its own in the body, and its own line from a trailing comment.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')

    function script:Get-Suppression {
        param([string]$Name, [string]$Body)
        $path = New-TestScript $Name $Body
        @(InModuleScope IntuneScriptLab -Parameters @{ Path = $path } {
                Get-IslSuppression -Context (Get-IslScriptContext -Path $Path)
            })
    }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Get-IslSuppression' -Tag 'Unit', 'Private' {

    It 'returns nothing for a script without a Suppress directive' {
        $body = "# IntuneScriptLab: ScriptType=Detection`nexit 0"
        @(Get-Suppression 'plain.ps1' $body).Count | Should-Be 0
    }

    It 'applies a header directive to the whole file, one entry per rule, with wildcards kept' {
        $body = @(
            '<#'
            '    .SYNOPSIS'
            '    A script'
            '#>'
            '# IntuneScriptLab: ScriptType=Remediation Suppress=IslLongSleep,IslOutput*'
            ''
            'Start-Sleep -Seconds 4000'
            'exit 0'
        ) -join "`n"
        $result = @(Get-Suppression 'header.ps1' $body)
        $result.Count | Should-Be 2
        $result[0].PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.Suppression'
        $result.Rule | Should-BeCollection @('IslLongSleep', 'IslOutput*')
        $result.Line | Should-All { $_ -eq 0 }
        $result[0].Source | Should-Be 5
    }

    It 'applies a directive on its own line in the body to the next line of code' {
        $body = @(
            'Write-Output "start"'
            ''
            '# IntuneScriptLab: Suppress=IslLongSleep'
            ''
            '# a comment in between does not count as code'
            'Start-Sleep -Seconds 4000'
            'exit 0'
        ) -join "`n"
        $result = @(Get-Suppression 'body.ps1' $body)
        $result.Count | Should-Be 1
        $result[0].Line | Should-Be 6
    }

    It 'applies a trailing directive to its own line' {
        $body = @(
            'Write-Output "start"'
            'Start-Sleep -Seconds 4000   # IntuneScriptLab: Suppress=IslLongSleep'
            'exit 0'
        ) -join "`n"
        $result = @(Get-Suppression 'trailing.ps1' $body)
        $result.Count | Should-Be 1
        $result[0].Line | Should-Be 2
    }

    It 'reads Suppress next to the other directive keys and ignores keys it does not know' {
        $body = "Write-Output 'x'`n# IntuneScriptLab: Context=User; Suppress=IslContextIssue; Other=1`nexit 0"
        $result = @(Get-Suppression 'mixed.ps1' $body)
        $result.Rule | Should-BeCollection @('IslContextIssue')
        $result[0].Line | Should-Be 3
    }

    It 'points a directive on the last line at itself' {
        $body = "exit 0`n# IntuneScriptLab: Suppress=IslExitCodeIssue"
        @(Get-Suppression 'last.ps1' $body)[0].Line | Should-Be 2
    }
}
