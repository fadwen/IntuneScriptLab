#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The runner's own gate: a run that executed nothing must fail. Pester's result for a run in which
    a filter left every test out is Passed, and its TotalCount still counts those tests, so the
    runner counts the tests that passed or failed. The runner is started in a new process with a
    filter that leaves out every unit test, this file's included.

    And what each test type selects, on a repository of its own: a copy of the runner, a module that
    is only a manifest, and one fixture file in Tests/Unit and one in Tests/Integration, with a
    test of each kind. The Integration tag, not the folder, decides what the unit run leaves out.
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

    # The fixture repository: the runner imports the manifest at its root and runs these suites
    $script:FixtureRoot = Join-Path -Path $TestDrive -ChildPath 'repository'
    $fixtureTests = Join-Path -Path $script:FixtureRoot -ChildPath 'Tests'
    $fixtureValidation = Join-Path -Path $script:FixtureRoot -ChildPath 'Validation'
    $fixtureValidation = Join-Path -Path $fixtureValidation -ChildPath 'Tests'
    $folders = @(
        (Join-Path -Path $fixtureTests -ChildPath 'Unit')
        (Join-Path -Path $fixtureTests -ChildPath 'Integration')
        (Join-Path -Path $fixtureValidation -ChildPath 'Unit')
    )
    foreach ($folder in $folders) {
        $null = New-Item -ItemType Directory -Path $folder -Force
    }
    Copy-Item -LiteralPath $script:runner -Destination $fixtureTests
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $rootModule = Join-Path -Path $script:FixtureRoot -ChildPath 'IntuneScriptLab.psm1'
    [System.IO.File]::WriteAllText($rootModule, '', $utf8)
    $manifest = "@{ RootModule = 'IntuneScriptLab.psm1'; ModuleVersion = '1.0.0'; FunctionsToExport = @() }"
    $manifestPath = Join-Path -Path $script:FixtureRoot -ChildPath 'IntuneScriptLab.psd1'
    [System.IO.File]::WriteAllText($manifestPath, $manifest, $utf8)
    $unitFixture = @(
        "Describe 'Fixture unit' -Tag 'Unit' {"
        "    It 'unit' { }"
        "    It 'process' -Tag 'Integration' { }"
        "    It 'unit security' -Tag 'Security' { }"
        '}'
    ) -join "`n"
    $unitFile = Join-Path -Path $folders[0] -ChildPath 'Fixture.Tests.ps1'
    [System.IO.File]::WriteAllText($unitFile, $unitFixture, $utf8)
    $integrationFixture = @(
        "Describe 'Fixture integration' -Tag 'Integration' {"
        "    It 'integration' { }"
        "    It 'integration security' -Tag 'Security' { }"
        '}'
    ) -join "`n"
    $integrationFile = Join-Path -Path $folders[1] -ChildPath 'Fixture.Tests.ps1'
    [System.IO.File]::WriteAllText($integrationFile, $integrationFixture, $utf8)
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

    Context 'What each test type runs' {
        It '-TestType <TestType> <Arguments> runs <Expected>' -Skip:$script:InsideRunner -ForEach @(
            @{ TestType = 'Unit'; Arguments = ''; Expected = 'unit, unit security' }
            @{ TestType = 'Unit'; Arguments = '-Tag Integration'; Expected = 'process' }
            @{ TestType = 'Unit'; Arguments = '-Tag Security'; Expected = 'unit security' }
            @{ TestType = 'Integration'; Arguments = ''; Expected = 'integration, integration security, process' }
            @{ TestType = 'Integration'; Arguments = '-Tag Security'; Expected = 'integration security' }
            @{
                TestType = 'All'; Arguments = ''
                Expected = 'integration, integration security, process, unit, unit security'
            }
        ) {
            $fixtureTests = Join-Path -Path $script:FixtureRoot -ChildPath 'Tests'
            $fixtureRunner = Join-Path -Path $fixtureTests -ChildPath 'Invoke-Tests.ps1'
            $run = "& '$fixtureRunner' -TestType $TestType $Arguments -Output None -PassThru 6>`$null"
            $names = "($run).Tests | Where-Object { `$_.Result -eq 'Passed' } | ForEach-Object { `$_.Name }"
            $command = "(@($names) | Sort-Object) -join ', '"
            $arguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', $command)
            $output = & $script:shell @arguments

            "$output" | Should-Be $Expected
            $LASTEXITCODE | Should-Be 0
        }
    }
}
