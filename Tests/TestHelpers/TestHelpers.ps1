<#
    Fixtures shared by the suites. Every suite dot-sources this file in its own BeforeAll, because
    Pester 6 discovers and runs one file at a time and nothing may rely on another file having
    run first.
#>

# The fixtures write only under TestDrive, which Pester removes; ShouldProcess would be noise
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
param()

function New-TestScript {
    <#
    .SYNOPSIS
        Writes a script under TestDrive and returns its path.

    .DESCRIPTION
        Creates the folders the name needs below TestDrive and writes the content in one of three
        encodings: UTF-8 without a byte order mark, UTF-8 with one, or UTF-16 LE with one. The
        encoding is part of what several rules and the runtime harness test, so it is chosen
        explicitly rather than left to the platform.

    .PARAMETER Name
        The path of the script relative to TestDrive, with any folders, such as
        'Remediations\Widget\Detect.ps1'.

    .PARAMETER Content
        The text of the script. An empty string writes an empty file.

    .PARAMETER Bom
        Writes UTF-8 with a byte order mark. Windows PowerShell 5.1 reads UTF-8 without one as
        ANSI, so the runtime suites want it on scripts that hold non-ASCII text.

    .PARAMETER Utf16
        Writes UTF-16 LE with a byte order mark instead of UTF-8.

    .EXAMPLE
        New-TestScript -Name 'Detect.ps1' -Content "Write-Output 'present'`r`nexit 0" -Bom

        Writes a detection script with a byte order mark and returns its full path.

    .INPUTS
        None.

    .OUTPUTS
        System.String. The full path of the script.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Content,

        [switch]$Bom,

        [switch]$Utf16
    )

    $path = Join-Path -Path $TestDrive -ChildPath $Name
    $null = New-Item -ItemType Directory -Path (Split-Path -Path $path -Parent) -Force
    $encoding = if ($Utf16) {
        [System.Text.Encoding]::Unicode
    } else {
        [System.Text.UTF8Encoding]::new([bool]$Bom)
    }
    [System.IO.File]::WriteAllText($path, $Content, $encoding)
    $path
}


function Get-RuleFinding {
    <#
    .SYNOPSIS
        Runs one private rule directly against a script and returns its findings.

    .DESCRIPTION
        Builds the script context with Get-IslScriptContext inside the module and calls the rule's
        Find- function with it, so that a rule suite tests the rule alone, without the rest of
        Test-IntuneScript. A lone finding comes back as a scalar, so callers wrap the call in @():
        Windows PowerShell 5.1 has no Count on a single object under strict mode.

    .PARAMETER Path
        The script to analyze.

    .PARAMETER Rule
        The rule name as it appears in findings, such as IslExitCodeIssue for the function
        Find-IslExitCodeIssue.

    .PARAMETER Options
        ScriptType, Context and Architecture for Get-IslScriptContext. Values that are left out are
        inferred, as they are for Test-IntuneScript.

    .EXAMPLE
        @(Get-RuleFinding -Path $script -Rule IslExitCodeIssue -Options @{ ScriptType = 'Detection' })

        Returns the exit code findings for a script analyzed as a remediation detection.

    .INPUTS
        None.

    .OUTPUTS
        IntuneScriptLab.Finding. One object for each finding of the rule.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.Finding')]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Rule,

        [hashtable]$Options = @{}
    )

    $parameters = @{ Path = $Path; Rule = $Rule; Options = $Options }
    InModuleScope IntuneScriptLab -Parameters $parameters {
        $scriptContext = Get-IslScriptContext -Path $Path @Options
        & "Find-$Rule" -Context $scriptContext
    }
}


function Get-AssertionMessage {
    <#
    .SYNOPSIS
        Runs an assertion that is expected to fail and returns its failure message.

    .DESCRIPTION
        The custom assertions report a failure by throwing with a message that names what Intune
        would report. The suites check that message, so this runs the assertion and returns the
        message of what it threw. An assertion that does not fail throws 'the assertion did not
        fail', whose message is returned the same way and fails the comparison in the test.

    .PARAMETER Assertion
        A script block that runs one assertion.

    .EXAMPLE
        Get-AssertionMessage -Assertion { $result | Should-BeIntuneDetected }

        Returns the failure message of the assertion for a result that is not detected.

    .INPUTS
        None.

    .OUTPUTS
        System.String. The message of the failure.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Assertion
    )

    try {
        & $Assertion
        throw 'the assertion did not fail'
    } catch [Exception] {
        # The failure is the result here: its message is what the test compares
        $_.Exception.Message
    }
}


function New-Win32Fixture {
    <#
    .SYNOPSIS
        Creates a Win32 content folder with an install.ps1, a detection script and a marker path.

    .DESCRIPTION
        Lays out what Invoke-IntuneWin32AppTest needs under TestDrive: a content folder that holds
        install.ps1, a detection script beside it, and the path of a marker file that the scripts
        can create and test for. Both scripts are written as UTF-8 with a byte order mark.

    .PARAMETER Name
        The folder under TestDrive that holds the fixture.

    .PARAMETER InstallBody
        The text of install.ps1.

    .PARAMETER DetectBody
        The text of the detection script.

    .EXAMPLE
        New-Win32Fixture -Name 'App' -InstallBody 'exit 0' -DetectBody "Write-Output 'x'`r`nexit 0"

        Creates the fixture and returns its content folder, detection script and marker path.

    .INPUTS
        None.

    .OUTPUTS
        IntuneScriptLab.Test.Win32Fixture. Content, Detection and Marker.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.Test.Win32Fixture')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$InstallBody,

        [Parameter(Mandatory)]
        [string]$DetectBody
    )

    $root = Join-Path -Path $TestDrive -ChildPath $Name
    $content = Join-Path -Path $root -ChildPath 'content'
    $null = New-Item -ItemType Directory -Path $content -Force
    $utf8Bom = [System.Text.UTF8Encoding]::new($true)
    [System.IO.File]::WriteAllText((Join-Path -Path $content -ChildPath 'install.ps1'), $InstallBody, $utf8Bom)
    $detect = Join-Path -Path $root -ChildPath 'detect.ps1'
    [System.IO.File]::WriteAllText($detect, $DetectBody, $utf8Bom)
    [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.Test.Win32Fixture'
        Content = $content
        Detection = $detect
        Marker = Join-Path -Path $root -ChildPath 'installed.marker'
    }
}


function Set-Win32FixtureScript {
    <#
    .SYNOPSIS
        Rewrites the install.ps1 and the detection script of a Win32 fixture.

    .DESCRIPTION
        Replaces the script that each given parameter names and leaves the other as it is, so that
        one fixture can serve the tests of a context with different scripts.

    .PARAMETER Fixture
        The fixture that New-Win32Fixture returned.

    .PARAMETER InstallBody
        The new text of install.ps1. Left out, install.ps1 is not changed.

    .PARAMETER DetectBody
        The new text of the detection script. Left out, the detection script is not changed.

    .EXAMPLE
        Set-Win32FixtureScript -Fixture $fixture -InstallBody 'exit 1603'

        Makes the install fail with exit code 1603 and keeps the detection script.

    .INPUTS
        None.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Fixture,

        [string]$InstallBody,

        [string]$DetectBody
    )

    $utf8Bom = [System.Text.UTF8Encoding]::new($true)
    if ($PSBoundParameters.ContainsKey('InstallBody')) {
        $installPath = Join-Path -Path $Fixture.Content -ChildPath 'install.ps1'
        [System.IO.File]::WriteAllText($installPath, $InstallBody, $utf8Bom)
    }
    if ($PSBoundParameters.ContainsKey('DetectBody')) {
        [System.IO.File]::WriteAllText($Fixture.Detection, $DetectBody, $utf8Bom)
    }
}


function ConvertTo-FakeRunResult {
    <#
    .SYNOPSIS
        Completes a partial run result with every member the real one has.

    .DESCRIPTION
        A mock of Invoke-IslScriptRun or Invoke-IslProcess names only the members its test is about.
        The commands read the others too, and under strict mode a read of a member that is not there
        is an error, so the fake gets the rest with the values of an uneventful run as SYSTEM, and
        the type name of the result it stands for.

    .PARAMETER Member
        The members the test sets, by name. Each replaces the default of that name.

    .PARAMETER TypeName
        The type name of the fake. IntuneScriptLab.RunResult, the default, is what
        Invoke-IslScriptRun returns; a mock of Invoke-IslProcess passes
        IntuneScriptLab.ProcessResult.

    .EXAMPLE
        ConvertTo-FakeRunResult @{ ExitCode = 1; StdOut = 'missing' }

        A run that exited 1 after writing one line, with every other member at its default.

    .INPUTS
        None.

    .OUTPUTS
        IntuneScriptLab.RunResult. The fake run result, or the type that -TypeName names.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.RunResult')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [hashtable]$Member,

        [ValidateSet('IntuneScriptLab.RunResult', 'IntuneScriptLab.ProcessResult')]
        [string]$TypeName = 'IntuneScriptLab.RunResult'
    )

    $result = [ordered]@{
        PSTypeName = $TypeName
        Phase = 'detection'
        ScriptPath = ''
        Host = 'powershell.exe'
        Architecture = 'x64'
        Context = 'System'
        RunAs = 'NT AUTHORITY\SYSTEM (Service)'
        UserName = 'NT AUTHORITY\SYSTEM'
        LogonType = 'Service'
        ExitCode = 0
        TimedOut = $false
        StdOut = ''
        StdErr = ''
        Duration = [timespan]::Zero
    }
    foreach ($key in $Member.Keys) {
        $result[$key] = $Member[$key]
    }
    [pscustomobject]$result
}


function Invoke-CallerScript {
    <#
    .SYNOPSIS
        Runs statements as a script in a new process that has no try and the default error preference.

    .DESCRIPTION
        A command that ends with a terminating error ends only itself for such a caller, and the test
        wants to know what the command did before it ended: did it stop where it failed, or did it go
        on with nothing where a result should be? Should-Throw cannot tell. It runs the call inside
        a try, and with a try anywhere above it every error travels all the way up.

        The script imports the module, runs the statements, and then writes the IDs of every error
        the session recorded, oldest first. A command that stopped where it failed leaves the IDs of
        that one failure. One that went on leaves the errors of the statements after it as well.

    .PARAMETER Statement
        The statements of the script, one to a line, after the import of the module.

    .PARAMETER Manifest
        The module manifest to import. The default is the one of this repository.

    .EXAMPLE
        Invoke-CallerScript -Statement "Get-IntuneAgentTimeline -Path 'C:\nowhere'"

        Runs the command against a folder that is not there and returns what the script wrote, the
        IDs of the errors and whether the script reached its end.

    .INPUTS
        None.

    .OUTPUTS
        IntuneScriptLab.Test.CallerScriptResult. Output, ErrorId, ReachedEnd and ExitCode.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.Test.CallerScriptResult')]
    param(
        [Parameter(Mandatory)]
        [string[]]$Statement,

        [Parameter()]
        [string]$Manifest
    )

    $manifestPath = $Manifest
    if (-not $manifestPath) {
        $repositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
        $manifestPath = Join-Path -Path $repositoryRoot -ChildPath 'IntuneScriptLab.psd1'
    }
    $folder = Join-Path -Path $TestDrive -ChildPath "caller-$([guid]::NewGuid().ToString('N'))"
    $null = New-Item -ItemType Directory -Path $folder -Force
    $script = Join-Path -Path $folder -ChildPath 'caller.ps1'
    $marker = 'CALLER-SCRIPT-'
    $lines = @(
        "Import-Module '$manifestPath'"
        $Statement
        # Oldest first; the session lists its errors newest first
        "`$ids = @(`$Error | ForEach-Object { `$_.FullyQualifiedErrorId }); [array]::Reverse(`$ids)"
        "'${marker}ERRORS:' + (`$ids -join '|')"
        "'${marker}END'"
    )
    [System.IO.File]::WriteAllLines($script, [string[]]$lines, [System.Text.UTF8Encoding]::new($true))

    # Files, not the pipeline: Windows PowerShell turns what a native command writes to a redirected
    # error stream into error records, and under a CI step's error preference those end the test
    $outFile = Join-Path -Path $folder -ChildPath 'out.txt'
    $errFile = Join-Path -Path $folder -ChildPath 'err.txt'
    $startParameters = @{
        FilePath = (Get-Process -Id $PID).Path
        ArgumentList = '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', "`"$script`""
        RedirectStandardOutput = $outFile
        RedirectStandardError = $errFile
        Wait = $true
        PassThru = $true
    }
    # Start-Process has -WindowStyle on Windows only
    if ($PSVersionTable.PSVersion.Major -lt 6 -or $IsWindows) {
        $startParameters['WindowStyle'] = 'Hidden'
    }
    $process = Start-Process @startParameters
    $written = @([System.IO.File]::ReadAllLines($outFile))
    $errorLine = @($written | Where-Object { $_.StartsWith("${marker}ERRORS:") }) | Select-Object -Last 1
    $errorIds = @()
    if ($errorLine) {
        $errorIds = @($errorLine.Substring("${marker}ERRORS:".Length) -split '\|' | Where-Object { $_ })
    }
    [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.Test.CallerScriptResult'
        Output = @($written | Where-Object { -not $_.StartsWith($marker) })
        ErrorId = $errorIds
        ReachedEnd = $written -contains "${marker}END"
        ExitCode = $process.ExitCode
    }
}
