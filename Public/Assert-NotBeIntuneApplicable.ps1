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

    try {
        Test-IslPesterAssertionSupport
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
    $assert = New-ShouldAssertion -Caller $PSCmdlet -Actual $Actual -Buffer $Input
    $Actual = $assert.Actual()

    if (-not $Actual.Applicable) { return }
    $assert.Fail(
        'Expected the requirement not to be met,<because> but <Reason>',
        @{ Because = $Because; Reason = "$($Actual.Reason)" })
}
