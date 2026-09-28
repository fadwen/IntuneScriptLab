function ConvertTo-IslCmTraceTime {
    <#
    .SYNOPSIS
        Turns a CMTrace time and date attribute pair into a DateTime.

    .DESCRIPTION
        time is HH:mm:ss with up to seven fractional digits and an optional UTC bias suffix
        (+000, -420); date is M-d-yyyy. The bias is dropped: the value is returned as the local
        time the agent wrote, which is what the other timestamps on the device (probe records,
        registry reports) use as well.

    .PARAMETER Time
        The time attribute, e.g. 09:06:34.5901742 or 09:06:34.590+000.

    .PARAMETER Date
        The date attribute, e.g. 9-25-2026.

    .EXAMPLE
        ConvertTo-IslCmTraceTime -Time '09:06:34.5901742' -Date '9-25-2026'

        2026-09-25 09:06:34.5901742 as a DateTime.
    #>
    [CmdletBinding()]
    [OutputType([datetime])]
    param(
        [Parameter(Mandatory)]
        [string]$Time,

        [Parameter(Mandatory)]
        [string]$Date
    )

    $timeMatch = [regex]::Match($Time, '^(\d{1,2}):(\d{2}):(\d{2})(?:\.(\d{1,7}))?')
    $dateMatch = [regex]::Match($Date, '^(\d{1,2})-(\d{1,2})-(\d{4})$')
    if (-not $timeMatch.Success -or -not $dateMatch.Success) {
        throw "Not a CMTrace timestamp: date=$Date time=$Time"
    }
    $timeParts = $timeMatch.Groups
    $dateParts = $dateMatch.Groups
    $value = [datetime]::new([int]$dateParts[3].Value, [int]$dateParts[1].Value, [int]$dateParts[2].Value,
        [int]$timeParts[1].Value, [int]$timeParts[2].Value, [int]$timeParts[3].Value)
    if ($timeParts[4].Success) {
        $value = $value.AddTicks([long]$timeParts[4].Value.PadRight(7, '0'))
    }
    $value
}
