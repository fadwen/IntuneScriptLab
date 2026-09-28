#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Should-HaveIntuneRunState against fabricated platform script results: passes on the matching
    state, fails otherwise, and the failure message quotes the state, exit code and (capped)
    output.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
    $script:Ok = [pscustomobject]@{
        PSTypeName    = 'IntuneScriptLab.PlatformScriptResult'
        RunState      = 'Success'
        ExitCode      = 0
        ResultMessage = 'done'
    }
    $script:Bad = [pscustomobject]@{
        PSTypeName    = 'IntuneScriptLab.PlatformScriptResult'
        RunState      = 'Failed'
        ExitCode      = 1
        ResultMessage = 'broken: ' + ('x' * 400)
    }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Assert-HaveIntuneRunState' -Tag 'Unit', 'Public' {

    Context 'Parameter Validation' {
        It 'is exported under its Should- alias' {
            (Get-Command Should-HaveIntuneRunState).ResolvedCommand.Name | Should-Be 'Assert-HaveIntuneRunState'
        }
    }

    Context 'Core Functionality' {
        It 'passes on the matching state' {
            $script:Ok | Should-HaveIntuneRunState 'Success'
            $script:Bad | Should-HaveIntuneRunState 'Failed'
        }

        It 'fails on another state' {
            { $script:Bad | Should-HaveIntuneRunState 'Success' } | Should-Throw
        }
    }

    Context 'Failure message' {
        It 'quotes the state, exit code and output, capped at 300 characters' {
            $message = Get-AssertionMessage {
                $script:Bad | Should-HaveIntuneRunState 'Success' -Because 'it must'
            }
            $message | Should-BeLikeString ("Expected run state 'Success', because it must, but got 'Failed' " +
                "(exit 1). Output: 'broken: *...'*")
            $message.Length | Should-BeLessThan 420
            $message | Should-NotBeLikeString '*<*>*'
        }
    }
}
