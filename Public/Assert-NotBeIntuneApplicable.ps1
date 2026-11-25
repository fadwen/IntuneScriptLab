function Assert-NotBeIntuneApplicable {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Asserts a requirement result fails its rule (Should-NotBeIntuneApplicable).
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

    if (-not $received.Applicable) { return }
    $assert.Fail(
        'Expected the requirement not to be met,<because> but <Reason>',
        @{ Because = $Because; Reason = "$($received.Reason)" })
}
