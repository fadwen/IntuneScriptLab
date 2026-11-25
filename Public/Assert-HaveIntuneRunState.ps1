function Assert-HaveIntuneRunState {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Asserts a platform script result's RunState (Should-HaveIntuneRunState).
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
        [object]$Actual,

        [string]$Because
    )

    try {
        Test-IslPesterAssertionSupport
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
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
