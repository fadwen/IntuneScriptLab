#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The CI gate script in Examples, run as a build would run it: in a child process of the host
    running the tests, against a folder of scripts with known findings, checking the exit code,
    the GitHub annotations on stdout and the Markdown summary it appends.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Gate = Join-Path $script:ModuleRoot 'Examples\Invoke-IntuneScriptGate.ps1'
    $script:HostExe = (Get-Process -Id $PID).Path
    $script:Scripts = Join-Path $TestDrive 'Intune'
    $utf8Bom = [System.Text.UTF8Encoding]::new($true)
    $null = New-Item -ItemType Directory -Path (Join-Path $script:Scripts 'Remediations\Widget') -Force
    $null = New-Item -ItemType Directory -Path (Join-Path $script:Scripts 'Clean') -Force
    # 'return' before 'exit 1' never triggers the remediation: an error-level finding
    [System.IO.File]::WriteAllText((Join-Path $script:Scripts 'Remediations\Widget\Detect.ps1'),
        "if (Test-Path C:\x) { return 'ok' }`r`nexit 1`r`n", $utf8Bom)
    [System.IO.File]::WriteAllText((Join-Path $script:Scripts 'Remediations\Widget\Remediate.ps1'),
        "Remove-Item C:\x -ErrorAction SilentlyContinue`r`nexit 0`r`n", $utf8Bom)
    [System.IO.File]::WriteAllText((Join-Path $script:Scripts 'Clean\Detect-Thing.ps1'),
        "Write-Output 'checked'`r`nexit 0`r`n", $utf8Bom)
    # A Pester suite next to the scripts, as the suite template places it: not an Intune script
    [System.IO.File]::WriteAllText((Join-Path $script:Scripts 'IntuneScripts.Tests.ps1'),
        "BeforeAll { Import-Module IntuneScriptLab }`r`nDescribe 'x' { It 'y' { 1 | Should-Be 1 } }`r`n", $utf8Bom)

    # -File carries the script's exit code out as the process exit code on both hosts; a switch
    # cannot be negated that way, so the quiet run uses -Command (and expects exit 0 anyway)
    function script:Invoke-GateFile {
        param([string[]]$Arguments)
        $output = & $script:HostExe -NoProfile -NonInteractive -File $script:Gate @Arguments 2>&1
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = @($output | ForEach-Object { "$_" }) }
    }
    function script:Invoke-GateCommand {
        param([string]$Arguments)
        $output = & $script:HostExe -NoProfile -NonInteractive -Command "& '$($script:Gate)' $Arguments" 2>&1
        @($output | ForEach-Object { "$_" })
    }
}

Describe 'Invoke-IntuneScriptGate' -Tag 'Integration', 'Gate' {

    It 'fails the build on an error-level finding and annotates it for GitHub' {
        $run = Invoke-GateFile -Arguments @('-Path', $script:Scripts, '-Annotate', '-Root', $script:Scripts)
        $run.ExitCode | Should-Be 1
        $errorLines = @($run.Output | Where-Object { $_ -like '::error file=*' })
        $errorLines.Count | Should-BeGreaterThan 0
        $errorLines[0] | Should-BeLikeString '::error file=Remediations/Widget/Detect.ps1,line=*,col=*::*'
        $errorLines[0] | Should-BeLikeString '*title=IslExitCodeIssue::*'
        ($run.Output -join "`n") | Should-BeLikeString '*failing the build*'
    }

    It 'passes with -FailOn None and with a clean folder, and stays quiet without -Annotate' {
        $none = Invoke-GateCommand -Arguments "-Path '$($script:Scripts)' -FailOn None -Annotate:`$false"
        @($none | Where-Object { $_ -like '::*' }).Count | Should-Be 0
        ($none -join "`n") | Should-BeLikeString '*IslExitCodeIssue*'
        $cleanFolder = Join-Path $script:Scripts 'Clean'
        $clean = Invoke-GateFile -Arguments @('-Path', $cleanFolder, '-ExcludeRule', 'IslAssumedContext')
        $clean.ExitCode | Should-Be 0
        ($clean.Output -join "`n") | Should-BeLikeString '*0 finding(s) in 0 script(s)*'
    }

    It 'fails on warnings when asked, and honours the rule filters' {
        $note = Invoke-GateFile -Arguments @('-Path', $script:Scripts, '-FailOn', 'Warning',
            '-IncludeRule', 'IslAssumedContext')
        # The assumed-context note is Information only
        $note.ExitCode | Should-Be 0
        ($note.Output -join "`n") | Should-BeLikeString '*IslAssumedContext*'
        $excluded = Invoke-GateFile -Arguments @('-Path', $script:Scripts, '-FailOn', 'None',
            '-ExcludeRule', 'IslExitCodeIssue')
        $excluded.ExitCode | Should-Be 0
        ($excluded.Output -join "`n") | Should-NotBeLikeString '*IslExitCodeIssue*'
    }

    It 'writes a SARIF log with -SarifPath, paths relative to -Root' {
        $sarifPath = Join-Path $TestDrive 'results.sarif'
        $run = Invoke-GateFile -Arguments @('-Path', $script:Scripts, '-SarifPath', $sarifPath,
            '-Root', $script:Scripts, '-FailOn', 'None')
        $run.ExitCode | Should-Be 0
        ($run.Output -join "`n") | Should-BeLikeString '*SARIF written to*'
        $sarif = Get-Content $sarifPath -Raw | ConvertFrom-Json
        $sarif.version | Should-Be '2.1.0'
        $exit = $sarif.runs[0].results | Where-Object ruleId -eq 'IslExitCodeIssue'
        $exit.locations[0].physicalLocation.artifactLocation.uri | Should-Be 'Remediations/Widget/Detect.ps1'
        $exit.level | Should-Be 'error'
    }

    It 'appends a Markdown summary with a row per finding' {
        $summary = Join-Path $TestDrive 'summary.md'
        [System.IO.File]::WriteAllText($summary, "existing`n")
        $run = Invoke-GateFile -Arguments @('-Path', $script:Scripts, '-SummaryPath', $summary,
            '-Root', $script:Scripts)
        $run.ExitCode | Should-Be 1
        $text = Get-Content $summary -Raw
        $text | Should-BeLikeString "existing`n## IntuneScriptLab: * finding(s) in * script(s)*"
        $text | Should-BeLikeString '*| Severity | Rule | Script | Line | Message |*'
        $text | Should-BeLikeString '*| Error | IslExitCodeIssue | Remediations/Widget/Detect.ps1 | *'
        $text | Should-BeLikeString '*gate: fail on Error.*'
    }

    It 'leaves a Pester suite under the folder out of the analysis, and analyzes one named directly' {
        $run = Invoke-GateFile -Arguments @('-Path', $script:Scripts, '-Annotate', '-Root', $script:Scripts,
            '-FailOn', 'None')
        $run.ExitCode | Should-Be 0
        ($run.Output -join "`n") | Should-NotBeLikeString '*IntuneScripts.Tests.ps1*'
        ($run.Output -join "`n") | Should-NotBeLikeString '*IslModuleDependency*'
        $direct = Invoke-GateFile -Arguments @('-Path', (Join-Path $script:Scripts 'IntuneScripts.Tests.ps1'),
            '-FailOn', 'None', '-Annotate:$false')
        ($direct.Output -join "`n") | Should-BeLikeString '*IslModuleDependency*'
    }

    It 'percent-encodes the colon of an absolute path outside -Root in the file property' {
        # With -Root below the scripts, every path stays absolute and carries a drive letter
        $run = Invoke-GateFile -Arguments @('-Path', $script:Scripts, '-Annotate', '-FailOn', 'None',
            '-Root', (Join-Path $script:Scripts 'Clean'))
        $errorLines = @($run.Output | Where-Object { $_ -like '::error file=*' })
        $errorLines.Count | Should-BeGreaterThan 0
        $fileValue = ([regex]::Match($errorLines[0], '^::error file=([^,]*),')).Groups[1].Value
        $fileValue | Should-NotBeLikeString '*:*'
        $fileValue | Should-BeLikeString '*%3A*Detect.ps1'
    }

    It 'returns the findings with -PassThru' {
        $output = Invoke-GateCommand -Arguments ("-Path '$($script:Scripts)' -FailOn None -PassThru " +
            "-Annotate:`$false | ForEach-Object { 'FINDING ' + `$_.RuleName }")
        @($output | Where-Object { $_ -eq 'FINDING IslExitCodeIssue' }).Count | Should-BeGreaterThan 0
    }
}
