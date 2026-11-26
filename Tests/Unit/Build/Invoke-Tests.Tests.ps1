#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The runner's own gate: a run that executed nothing must fail. Pester's result for a run in which
    a filter left every test out is Passed, and its TotalCount still counts those tests, so the
    runner counts the tests that passed or failed. The runner is started in a new process with a
    filter that leaves out every unit test, this file's included.
#>

BeforeDiscovery {
    # The run started below discovers this file too. Its tag leaves the test out there; this is
    # the second guard, so that a change of tags cannot make the runner start itself without end
    $script:InsideRunner = [bool]$env:ISL_RUNNER_SELF_TEST
}

BeforeAll {
    $repositoryRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    $testsFolder = Join-Path -Path $repositoryRoot -ChildPath 'Tests'
    $script:runner = Join-Path -Path $testsFolder -ChildPath 'Invoke-Tests.ps1'
    $script:shell = (Get-Process -Id $PID).Path
}

Describe 'Invoke-Tests.ps1' -Tag 'Integration', 'Build' {

    Context 'Error Handling' {
        It 'fails when a filter leaves every test out' -Skip:$script:InsideRunner {
            # The child reports on its output: its error stream, read under an error preference
            # of Stop, which a CI step sets, would end this test instead
            $run = "& '$script:runner' -TestType Unit -ExcludeTag Unit -Output None 6>`$null"
            $command = "try { $run; 'passed' } catch { 'failed: ' + `$_.Exception.Message; exit 1 }"
            $arguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', $command)
            $env:ISL_RUNNER_SELF_TEST = '1'
            try {
                $output = & $script:shell @arguments
                $exitCode = $LASTEXITCODE
            } finally {
                Remove-Item -Path Env:ISL_RUNNER_SELF_TEST
            }

            "$output" | Should-BeLikeString 'failed: Pester ran no tests for*left out by a filter.'
            $exitCode | Should-Be 1
        }
    }
}
