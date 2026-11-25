function Assert-BeIntuneDetected {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Asserts a detection result counts as installed (Should-BeIntuneDetected).
    #>
    [CmdletBinding()]
    [OutputType([void])]
    # Exception to FUN-21: New-ShouldAssertion reads the whole pipeline from $Input, which only the
    # end block holds. In a process block each piped item would be asserted on its own, and a
    # collection such as Get-ChildItem's output could not be asserted as one value.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseProcessBlockForPipelineCommand', '',
        Justification = 'New-ShouldAssertion reads the whole pipeline from $Input in the end block.')]
    param(
        [Parameter(Position = 0, ValueFromPipeline)]
        [object]$Actual,

        [string]$Because
    )

    try {
        Test-IslPesterAssertionSupport
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
    $assert = New-ShouldAssertion -Caller $PSCmdlet -Actual $Actual -Buffer $Input
    $received = $assert.Actual()

    if ($received.Detected) { return }
    $assert.Fail(
        'Expected the app to be detected,<because> but Intune would report not detected: <Reason>',
        @{ Because = $Because; Reason = "$($received.Reason)" })
}
