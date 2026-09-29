# Pester 6.2+ assertions for the harness results and the analyzer, in the shape the repository's
# custom-assertion guide prescribes: Assert-* functions built on New-ShouldAssertion, exported under
# Should-* aliases (Set-Alias in the module file). Each fails with the diagnosis Intune would give.

function Test-IslPesterAssertionSupport {
    # New-ShouldAssertion arrived in Pester 6.2; without it these functions cannot report properly.
    if (-not (Get-Command -Name New-ShouldAssertion -ErrorAction SilentlyContinue)) {
        throw 'The IntuneScriptLab assertions need Pester 6.2 or later loaded (Import-Module Pester)'
    }
}

function Assert-HaveIntuneStatus {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Asserts a remediation or Win32 result Status (alias Should-HaveIntuneStatus).
    #>
    [CmdletBinding()]
    [OutputType([void])]
    # The assertion body must be an end block so New-ShouldAssertion sees the whole pipeline (repo
    # custom-assertion guide)
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseProcessBlockForPipelineCommand', '')]
    param(
        [Parameter(Position = 0, Mandatory)]
        [string]$Expected,

        [Parameter(Position = 1, ValueFromPipeline)]
        $Actual,

        [string]$Because
    )

    Test-IslPesterAssertionSupport
    $assert = New-ShouldAssertion -Caller $PSCmdlet -Actual $Actual -Buffer $Input
    $Actual = $assert.Actual()

    $status = "$($Actual.Status)"
    if ($status -eq $Expected) { return }

    $detail = @()
    foreach ($name in 'IntuneOutput', 'IntuneError') {
        if ($Actual.PSObject.Properties[$name] -and $Actual.$name) { $detail += "${name}: $($Actual.$name)" }
    }
    if ($Actual.PSObject.Properties['Warnings'] -and $Actual.Warnings) {
        $detail += "Warnings: $($Actual.Warnings -join ' | ')"
    }
    $assert.Fail(
        'Expected status <expected>,<because> but Intune would report <Status>. <Detail>',
        @{ Expected = $Expected; Because = $Because; Status = $status; Detail = ($detail -join '. ') })
}

function Assert-BeIntuneDetected {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Asserts a Win32 detection result counts as installed (alias Should-BeIntuneDetected).
    #>
    [CmdletBinding()]
    [OutputType([void])]
    # The assertion body must be an end block so New-ShouldAssertion sees the whole pipeline (repo
    # custom-assertion guide)
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseProcessBlockForPipelineCommand', '')]
    param(
        [Parameter(Position = 0, ValueFromPipeline)]
        $Actual,

        [string]$Because
    )

    Test-IslPesterAssertionSupport
    $assert = New-ShouldAssertion -Caller $PSCmdlet -Actual $Actual -Buffer $Input
    $Actual = $assert.Actual()

    if ($Actual.Detected) { return }
    $assert.Fail(
        'Expected the app to be detected,<because> but Intune would report not detected: <Reason>',
        @{ Because = $Because; Reason = "$($Actual.Reason)" })
}

function Assert-NotBeIntuneDetected {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Asserts a Win32 detection result counts as not installed (alias Should-NotBeIntuneDetected).
    #>
    [CmdletBinding()]
    [OutputType([void])]
    # The assertion body must be an end block so New-ShouldAssertion sees the whole pipeline (repo
    # custom-assertion guide)
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseProcessBlockForPipelineCommand', '')]
    param(
        [Parameter(Position = 0, ValueFromPipeline)]
        $Actual,

        [string]$Because
    )

    Test-IslPesterAssertionSupport
    $assert = New-ShouldAssertion -Caller $PSCmdlet -Actual $Actual -Buffer $Input
    $Actual = $assert.Actual()

    if (-not $Actual.Detected) { return }
    $assert.Fail(
        ('Expected the app not to be detected,<because> but exit <ExitCode> with stdout <StdOut> counts as ' +
            'installed.'),
        @{ Because = $Because; ExitCode = $Actual.ExitCode; StdOut = "$($Actual.StdOut)".Trim() })
}

function Assert-HaveIntuneRunState {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Asserts the RunState of a platform script result (alias Should-HaveIntuneRunState).
    #>
    [CmdletBinding()]
    [OutputType([void])]
    # The assertion body must be an end block so New-ShouldAssertion sees the whole pipeline (repo
    # custom-assertion guide)
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseProcessBlockForPipelineCommand', '')]
    param(
        [Parameter(Position = 0, Mandatory)]
        [string]$Expected,

        [Parameter(Position = 1, ValueFromPipeline)]
        $Actual,

        [string]$Because
    )

    Test-IslPesterAssertionSupport
    $assert = New-ShouldAssertion -Caller $PSCmdlet -Actual $Actual -Buffer $Input
    $Actual = $assert.Actual()

    $state = "$($Actual.RunState)"
    if ($state -eq $Expected) { return }
    $output = "$($Actual.ResultMessage)"
    if ($output.Length -gt 300) { $output = $output.Substring(0, 300) + '...' }
    $assert.Fail(
        'Expected run state <expected>,<because> but got <State> (exit <ExitCode>). Output: <Output>',
        @{ Expected = $Expected; Because = $Because; State = $state; ExitCode = $Actual.ExitCode
           Output = $output })
}

function Assert-PassIntuneAnalysis {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Asserts Test-IntuneScript finds nothing at Warning or above (alias Should-PassIntuneAnalysis).
    #>
    [CmdletBinding()]
    [OutputType([void])]
    # The assertion body must be an end block so New-ShouldAssertion sees the whole pipeline (repo
    # custom-assertion guide)
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseProcessBlockForPipelineCommand', '')]
    param(
        [Parameter(Position = 0, ValueFromPipeline)]
        $Actual,

        [ValidateSet('Information', 'Warning', 'Error')]
        [string]$MinimumSeverity = 'Warning',

        [ValidateSet('Auto', 'Detection', 'Remediation', 'PlatformScript', 'Win32Detection', 'Win32Requirement')]
        [string]$ScriptType = 'Auto',

        [string]$Because
    )

    Test-IslPesterAssertionSupport
    # A file, a folder, or a pipeline of either: every script found is analyzed and the failure
    # names each file
    $assert = New-ShouldAssertion -Caller $PSCmdlet -Actual $Actual -Buffer $Input
    $Actual = $assert.Actual()
    $paths = @(foreach ($item in @($Actual)) {
            if ($item -is [System.IO.FileSystemInfo]) { $item.FullName } else { "$item" }
        })

    $findings = @(Test-IntuneScript -Path $paths -ScriptType $ScriptType -MinimumSeverity $MinimumSeverity |
            Where-Object { $_.RuleName -ne 'IslAssumedContext' })
    if ($findings.Count -eq 0) { return }

    $list = ($findings | ForEach-Object {
            "  $(Split-Path -Path $_.ScriptPath -Leaf):$($_.Line) [$($_.Severity)] $($_.RuleName): $($_.Message)"
        }) -join "`n"
    $assert.Fail(
        'Expected no Test-IntuneScript findings at <MinimumSeverity> or above,<because> but got ' +
            '<Count>:' + "`n" + '<List>',
        @{ Because = $Because; MinimumSeverity = $MinimumSeverity; Count = $findings.Count; List = $list })
}

function Assert-BeIntuneApplicable {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Asserts a requirement result meets its rule (alias Should-BeIntuneApplicable).
    #>
    [CmdletBinding()]
    [OutputType([void])]
    # The assertion body must be an end block so New-ShouldAssertion sees the whole pipeline (repo
    # custom-assertion guide)
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseProcessBlockForPipelineCommand', '')]
    param(
        [Parameter(Position = 0, ValueFromPipeline)]
        $Actual,

        [string]$Because
    )

    Test-IslPesterAssertionSupport
    $assert = New-ShouldAssertion -Caller $PSCmdlet -Actual $Actual -Buffer $Input
    $Actual = $assert.Actual()

    if ($Actual.Applicable) { return }
    $assert.Fail(
        'Expected the requirement to be met,<because> but Intune would report not applicable: <Reason>',
        @{ Because = $Because; Reason = "$($Actual.Reason)" })
}

function Assert-NotBeIntuneApplicable {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Asserts a requirement result fails its rule (alias Should-NotBeIntuneApplicable).
    #>
    [CmdletBinding()]
    [OutputType([void])]
    # The assertion body must be an end block so New-ShouldAssertion sees the whole pipeline (repo
    # custom-assertion guide)
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseProcessBlockForPipelineCommand', '')]
    param(
        [Parameter(Position = 0, ValueFromPipeline)]
        $Actual,

        [string]$Because
    )

    Test-IslPesterAssertionSupport
    $assert = New-ShouldAssertion -Caller $PSCmdlet -Actual $Actual -Buffer $Input
    $Actual = $assert.Actual()

    if (-not $Actual.Applicable) { return }
    $assert.Fail(
        'Expected the requirement not to be met,<because> but <Reason>',
        @{ Because = $Because; Reason = "$($Actual.Reason)" })
}
