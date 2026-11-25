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

    try {
        Test-IslPesterAssertionSupport
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
    $assert = New-ShouldAssertion -Caller $PSCmdlet -Actual $Actual -Buffer $Input
    $Actual = $assert.Actual()

    if ($Actual.Detected) { return }
    $assert.Fail(
        'Expected the app to be detected,<because> but Intune would report not detected: <Reason>',
        @{ Because = $Because; Reason = "$($Actual.Reason)" })
}
