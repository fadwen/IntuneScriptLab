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
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Content,

        # Windows PowerShell 5.1 reads UTF-8 without a BOM as ANSI; runtime scripts want the BOM
        [switch]$Bom,

        [switch]$Utf16
    )
    $path = Join-Path $TestDrive $Name
    $null = New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force
    $encoding = if ($Utf16) { [System.Text.Encoding]::Unicode }
    else { [System.Text.UTF8Encoding]::new([bool]$Bom) }
    [System.IO.File]::WriteAllText($path, $Content, $encoding)
    $path
}

function Get-RuleFinding {
    <#
    .SYNOPSIS
        Runs one private rule directly against a script and returns its findings as an array.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        # The rule name as it appears in findings, e.g. IslExitCodeIssue (function Find-IslExitCodeIssue)
        [Parameter(Mandatory)]
        [string]$Rule,

        # ScriptType, Context and Architecture for Get-IslScriptContext; unset ones are inferred
        [hashtable]$Options = @{}
    )
    # Callers wrap the result in @(): a lone finding unrolls to a scalar, which has no .Count on
    # Windows PowerShell 5.1 (it reads as $null there and as 1 on PowerShell 7)
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
    #>
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Assertion
    )
    try {
        & $Assertion
        throw 'the assertion did not fail'
    }
    catch [Exception] {
        $_.Exception.Message
    }
}

function New-Win32Fixture {
    <#
    .SYNOPSIS
        A Win32 content folder with an install.ps1, a detection script and a marker path.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$InstallBody,

        [Parameter(Mandatory)]
        [string]$DetectBody
    )
    $root = Join-Path $TestDrive $Name
    $content = Join-Path $root 'content'
    $null = New-Item -ItemType Directory -Path $content -Force
    $utf8Bom = [System.Text.UTF8Encoding]::new($true)
    [System.IO.File]::WriteAllText((Join-Path $content 'install.ps1'), $InstallBody, $utf8Bom)
    $detect = Join-Path $root 'detect.ps1'
    [System.IO.File]::WriteAllText($detect, $DetectBody, $utf8Bom)
    [pscustomobject]@{
        Content   = $content
        Detection = $detect
        Marker    = Join-Path $root 'installed.marker'
    }
}

function Set-Win32FixtureScript {
    <#
    .SYNOPSIS
        Rewrites the install.ps1 and detection script of a Win32 fixture.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Fixture,

        [string]$InstallBody,

        [string]$DetectBody
    )
    $utf8Bom = [System.Text.UTF8Encoding]::new($true)
    if ($PSBoundParameters.ContainsKey('InstallBody')) {
        [System.IO.File]::WriteAllText((Join-Path $Fixture.Content 'install.ps1'), $InstallBody, $utf8Bom)
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
        is an error, so the fake gets the rest with the values of an uneventful run as SYSTEM.

    .PARAMETER Member
        The members the test sets, by name. Each replaces the default of that name.

    .EXAMPLE
        ConvertTo-FakeRunResult @{ ExitCode = 1; StdOut = 'missing' }

        A run that exited 1 after writing one line, with every other member at its default.

    .INPUTS
        None.

    .OUTPUTS
        System.Management.Automation.PSCustomObject. The fake run result.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [hashtable]$Member
    )
    $result = [ordered]@{
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
        System.Management.Automation.PSCustomObject. Output, ErrorId, ReachedEnd and ExitCode.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string[]]$Statement,

        [Parameter()]
        [string]$Manifest
    )

    if (-not $Manifest) {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $Manifest = Join-Path $repositoryRoot 'IntuneScriptLab.psd1'
    }
    $folder = Join-Path $TestDrive "caller-$([guid]::NewGuid().ToString('N'))"
    $null = New-Item -ItemType Directory -Path $folder -Force
    $script = Join-Path $folder 'caller.ps1'
    $marker = 'CALLER-SCRIPT-'
    $lines = @(
        "Import-Module '$Manifest'"
        $Statement
        # Oldest first; the session lists its errors newest first
        "`$ids = @(`$Error | ForEach-Object { `$_.FullyQualifiedErrorId }); [array]::Reverse(`$ids)"
        "'${marker}ERRORS:' + (`$ids -join '|')"
        "'${marker}END'"
    )
    [System.IO.File]::WriteAllLines($script, [string[]]$lines, [System.Text.UTF8Encoding]::new($true))

    # Files, not the pipeline: Windows PowerShell turns what a native command writes to a redirected
    # error stream into error records, and under a CI step's error preference those end the test
    $outFile = Join-Path $folder 'out.txt'
    $errFile = Join-Path $folder 'err.txt'
    $startParameters = @{
        FilePath = (Get-Process -Id $PID).Path
        ArgumentList = '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', "`"$script`""
        RedirectStandardOutput = $outFile
        RedirectStandardError = $errFile
        WindowStyle = 'Hidden'
        Wait = $true
        PassThru = $true
    }
    $process = Start-Process @startParameters
    $written = @([System.IO.File]::ReadAllLines($outFile))
    $errorLine = @($written | Where-Object { $_.StartsWith("${marker}ERRORS:") }) | Select-Object -Last 1
    $errorIds = @()
    if ($errorLine) {
        $errorIds = @($errorLine.Substring("${marker}ERRORS:".Length) -split '\|' | Where-Object { $_ })
    }
    [pscustomobject]@{
        Output = @($written | Where-Object { -not $_.StartsWith($marker) })
        ErrorId = $errorIds
        ReachedEnd = $written -contains "${marker}END"
        ExitCode = $process.ExitCode
    }
}
