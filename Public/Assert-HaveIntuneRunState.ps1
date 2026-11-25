function Assert-HaveIntuneRunState {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Asserts a platform script result's RunState (Should-HaveIntuneRunState).
    #>
    [CmdletBinding()]
    [OutputType([void])]
    # Exception to FUN-21: New-ShouldAssertion reads the whole pipeline from $Input, which only the
    # end block holds. In a process block each piped item would be asserted on its own, and a
    # collection such as Get-ChildItem's output could not be asserted as one value.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseProcessBlockForPipelineCommand', '',
        Justification = 'New-ShouldAssertion reads the whole pipeline from $Input in the end block.')]
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
    $received = $assert.Actual()

    $state = "$($received.RunState)"
    if ($state -eq $Expected) { return }
    $output = "$($received.ResultMessage)"
    if ($output.Length -gt 300) { $output = $output.Substring(0, 300) + '...' }
    $assert.Fail(
        'Expected run state <expected>,<because> but got <State> (exit <ExitCode>). Output: <Output>',
        @{ Expected = $Expected; Because = $Because; State = $state; ExitCode = $received.ExitCode
            Output = $output
        })
}
