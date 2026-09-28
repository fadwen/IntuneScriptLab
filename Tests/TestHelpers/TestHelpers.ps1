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
