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

    try {
        Test-IslPesterAssertionSupport
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
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
