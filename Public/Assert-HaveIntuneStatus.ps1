function Assert-HaveIntuneStatus {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Asserts a remediation or Win32 result Status (alias Should-HaveIntuneStatus).
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

    $status = "$($received.Status)"
    if ($status -eq $Expected) { return }

    $detail = @(
        foreach ($name in 'IntuneOutput', 'IntuneError') {
            if ($received.PSObject.Properties[$name] -and $received.$name) { "${name}: $($received.$name)" }
        }
        if ($received.PSObject.Properties['Warnings'] -and $received.Warnings) {
            "Warnings: $($received.Warnings -join ' | ')"
        }
    )
    $assert.Fail(
        'Expected status <expected>,<because> but Intune would report <Status>. <Detail>',
        @{ Expected = $Expected; Because = $Because; Status = $status; Detail = ($detail -join '. ') })
}
