function Assert-PassIntuneAnalysis {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Asserts no finding at Warning or above (Should-PassIntuneAnalysis).
    #>
    [CmdletBinding()]
    [OutputType([void])]
    # The assertion body must be an end block so New-ShouldAssertion sees the whole pipeline (repo
    # custom-assertion guide)
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseProcessBlockForPipelineCommand', '')]
    param(
        [Parameter(Position = 0, ValueFromPipeline)]
        [object]$Actual,

        [ValidateSet('Information', 'Warning', 'Error')]
        [string]$MinimumSeverity = 'Warning',

        [ValidateSet('Auto', 'Detection', 'Remediation', 'PlatformScript', 'Win32Detection', 'Win32Requirement')]
        [string]$ScriptType = 'Auto',

        [string]$Because
    )

    try {
        Test-IslPesterAssertionSupport
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
    # A file, a folder, or a pipeline of either: every script found is analyzed and the failure
    # names each file
    $assert = New-ShouldAssertion -Caller $PSCmdlet -Actual $Actual -Buffer $Input
    $received = $assert.Actual()
    $paths = @(foreach ($item in @($received)) {
            if ($item -is [System.IO.FileSystemInfo]) { $item.FullName } else { "$item" }
        })

    # A path that cannot be analyzed fails the assertion with its error. Test-IntuneScript reports
    # such a path and goes on, and with nothing analyzed there is no finding: the assertion
    # would pass
    $analysisSplat = @{
        Path = $paths; ScriptType = $ScriptType; MinimumSeverity = $MinimumSeverity; ErrorAction = 'Stop'
    }
    try {
        $findings = @(Test-IntuneScript @analysisSplat | Where-Object { $_.RuleName -ne 'IslAssumedContext' })
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
    if ($findings.Count -eq 0) { return }

    $list = ($findings | ForEach-Object {
            "  $(Split-Path -Path $_.ScriptPath -Leaf):$($_.Line) [$($_.Severity)] $($_.RuleName): $($_.Message)"
        }) -join "`n"
    $assert.Fail(
        'Expected no Test-IntuneScript findings at <MinimumSeverity> or above,<because> but got ' +
            '<Count>:' + "`n" + '<List>',
        @{ Because = $Because; MinimumSeverity = $MinimumSeverity; Count = $findings.Count; List = $list })
}
