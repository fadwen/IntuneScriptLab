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

    try {
        Test-IslPesterAssertionSupport
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
    $assert = New-ShouldAssertion -Caller $PSCmdlet -Actual $Actual -Buffer $Input
    $Actual = $assert.Actual()

    if (-not $Actual.Detected) { return }
    $assert.Fail(
        ('Expected the app not to be detected,<because> but exit <ExitCode> with stdout <StdOut> counts as ' +
            'installed.'),
        @{ Because = $Because; ExitCode = $Actual.ExitCode; StdOut = "$($Actual.StdOut)".Trim() })
}
