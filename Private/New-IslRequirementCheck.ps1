function New-IslRequirementCheck {
    <#
    .SYNOPSIS
    Builds the result of one requirement that Test-IntuneWin32Requirement checks.

    .DESCRIPTION
    One requirement of a Win32 app, such as the architecture or the free disk space, compared
    with this device. A check that is met carries no details and no applicability code; one that
    is not met carries the text and the code the agent was observed to report for it.

    .PARAMETER Requirement
    The name of the requirement, such as Architecture or MinimumFreeDiskSpaceMB.

    .PARAMETER Met
    Whether the device meets the requirement.

    .PARAMETER Actual
    What the device has, such as its architecture or its free space.

    .PARAMETER Expected
    What the requirement asks for.

    .PARAMETER Details
    The agent's text for a requirement that is not met.

    .PARAMETER Code
    The applicability code the agent reports for a requirement that is not met, such as 1000.
    Left out where no code was observed.

    .EXAMPLE
    $checkSplat = @{ Requirement = 'Architecture'; Met = $false; Actual = 'arm64'; Expected = 'x64' }
    New-IslRequirementCheck @checkSplat -Code 1000 -Details 'Device architecture is not applicable.'

    A check that the device does not meet, with the agent's code and text.

    .INPUTS
    None.

    .OUTPUTS
    IntuneScriptLab.RequirementCheck. Requirement, Met, Actual, Expected, Details and
    Applicability.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.RequirementCheck')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Builds an object and changes nothing.')]
    param(
        [Parameter(Mandatory)]
        [string]$Requirement,

        [Parameter()]
        [switch]$Met,

        [Parameter()]
        [AllowNull()]
        [object]$Actual,

        [Parameter()]
        [AllowNull()]
        [object]$Expected,

        [Parameter()]
        [string]$Details = '',

        [Parameter()]
        [AllowNull()]
        [object]$Code
    )

    [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.RequirementCheck'
        Requirement = $Requirement
        Met = [bool]$Met
        Actual = $Actual
        Expected = $Expected
        Details = if ($Met) { '' } else { $Details }
        Applicability = if ($Met) { $null } else { $Code }
    }
}
