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
    # A Win32 app's package content, as the suite template lays it out: the installer runs through
    # the install command as SYSTEM, so it is not an Intune script either. Read as one, its
    # machine-wide write is a user-context warning. 'Packages' is a folder of Win32 apps and stays in.
    $null = New-Item -ItemType Directory -Path (Join-Path $script:Scripts 'Win32\Widget\Package') -Force
    $null = New-Item -ItemType Directory -Path (Join-Path $script:Scripts 'Packages\Gadget') -Force
    [System.IO.File]::WriteAllText((Join-Path $script:Scripts 'Win32\Widget\Package\install.ps1'),
        "New-Item -Path HKLM:\SOFTWARE\Widget -Force | Out-Null`r`nexit 0`r`n", $utf8Bom)
    [System.IO.File]::WriteAllText((Join-Path $script:Scripts 'Packages\Gadget\Detect.ps1'),
        "Write-Output 'installed'`r`nexit 0`r`n", $utf8Bom)

    # -File carries the script's exit code out as the process exit code on both hosts; a switch
    # cannot be negated that way, so the quiet run uses -Command (and expects exit 0 anyway)
    function script:Invoke-GateFile {
        <#
        .SYNOPSIS
            Runs the gate script with -File in a child host and returns its exit code.

        .DESCRIPTION
            Starts the host that runs the tests on Invoke-IntuneScriptGate.ps1 with -File, so that
            the script's exit code becomes the process exit code, and collects stdout and stderr
            together as text.

        .PARAMETER Arguments
            The arguments for the gate script, one element for each parameter name and value.

        .EXAMPLE
            Invoke-GateFile -Arguments @('-Path', $script:Scripts, '-FailOn', 'None')

            Runs the gate on the script folder and returns its exit code and the lines it wrote.

        .INPUTS
            None.

        .OUTPUTS
            IntuneScriptLab.Test.GateRun. An object with ExitCode and Output, the lines as strings.
        #>
        [CmdletBinding()]
        [OutputType('IntuneScriptLab.Test.GateRun')]
        param(
            [string[]]$Arguments
        )

        $output = & $script:HostExe -NoProfile -NonInteractive -File $script:Gate @Arguments 2>&1
        [pscustomobject]@{
            PSTypeName = 'IntuneScriptLab.Test.GateRun'
            ExitCode = $LASTEXITCODE
            Output = @($output | ForEach-Object { "$_" })
        }
    }
    function script:Invoke-GateCommand {
        <#
        .SYNOPSIS
            Runs the gate script with -Command in a child host and returns its output.

        .DESCRIPTION
            Starts the host that runs the tests with -Command and the gate script called on the
            given argument text. Unlike -File, -Command can pass a negated switch such as
            -Annotate:$false. Stdout and stderr come back together as text.

        .PARAMETER Arguments
            The argument text for the gate script, as it would be typed after the script path.

        .EXAMPLE
            Invoke-GateCommand -Arguments "-Path '$($script:Scripts)' -FailOn None -Annotate:`$false"

            Runs the gate without annotations and returns the lines it wrote.

        .INPUTS
            None.

        .OUTPUTS
            System.String. One string for each line the gate wrote.
        #>
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [string]$Arguments
        )

        $output = & $script:HostExe -NoProfile -NonInteractive -Command "& '$($script:Gate)' $Arguments" 2>&1
        $output | ForEach-Object { "$_" }
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

    It 'fails, and says why, when a script cannot be analyzed' {
        # The analysis reports such a script and goes on with the others; a gate that went on too
        # would pass on scripts nobody looked at
        $folder = Join-Path $TestDrive 'Unreadable'
        $null = New-Item -ItemType Directory -Path $folder -Force
        $utf8Bom = [System.Text.UTF8Encoding]::new($true)
        [System.IO.File]::WriteAllText((Join-Path $folder 'Detect-Thing.ps1'),
            "Write-Output 'checked'`r`nexit 0`r`n", $utf8Bom)
        Set-Content -LiteralPath (Join-Path $folder 'IntuneScriptLab.settings.psd1') -Encoding ascii -Value (
            "@{ MinimumSeverity = 'Fatal' }")

        # Called from a command, as another script calls it, and not with -File: started with
        # -File the gate runs in the global scope, where its own error preference reaches the
        # module, and the test would pass without the gate asking the analysis to stop.
        # The error stream goes to a file: read with 2>&1, Windows PowerShell 5.1 turns each line
        # of it into an error record of this test
        $outFile = Join-Path $TestDrive 'gate-out.txt'
        $errFile = Join-Path $TestDrive 'gate-err.txt'
        $call = "& '$($script:Gate)' -Path '$folder'"
        $processSplat = @{
            FilePath = $script:HostExe
            ArgumentList = "-NoProfile -NonInteractive -Command `"$call`""
            RedirectStandardOutput = $outFile
            RedirectStandardError = $errFile
            Wait = $true
            PassThru = $true
            WindowStyle = 'Hidden'
        }
        $gate = Start-Process @processSplat
        $written = (Get-Content -LiteralPath $outFile, $errFile) -join ' '

        $gate.ExitCode | Should-NotBe 0
        # The host wraps the error to its own width, so only the name of the setting is looked for
        $written | Should-BeLikeString '*MinimumSeverity*'
        $written | Should-NotBeLikeString '*finding(s) in*'
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
            '-FailOn', 'None')
        ($direct.Output -join "`n") | Should-BeLikeString '*IslModuleDependency*'
    }

    It 'leaves a Win32 Package folder out, keeps a Packages folder in, and analyzes a named installer' {
        $run = Invoke-GateFile -Arguments @('-Path', $script:Scripts, '-Annotate', '-Root', $script:Scripts,
            '-FailOn', 'None')
        $run.ExitCode | Should-Be 0
        ($run.Output -join "`n") | Should-NotBeLikeString '*Package\install.ps1*'
        ($run.Output -join "`n") | Should-BeLikeString '*Packages\Gadget\Detect.ps1*'
        $installer = Join-Path $script:Scripts 'Win32\Widget\Package\install.ps1'
        $direct = Invoke-GateFile -Arguments @('-Path', $installer, '-FailOn', 'None')
        ($direct.Output -join "`n") | Should-BeLikeString '*IslContextIssue*'
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
