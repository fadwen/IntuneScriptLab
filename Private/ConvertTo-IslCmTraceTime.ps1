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

    # This runs once per log entry. The bias is cut off at the first + or - after the seconds, and
    # one TryParseExact reads the rest: the F specifiers take any number of fraction digits up to
    # seven, and none at all
    $bias = $Time.IndexOfAny([char[]]@('+', '-'), [Math]::Min(7, $Time.Length))
    $plain = if ($bias -ge 0) { $Time.Substring(0, $bias) } else { $Time }
    $value = [datetime]::MinValue
    $parsed = [datetime]::TryParseExact("$Date $plain", $script:IslCmTraceTimeFormat,
        [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$value)
    if (-not $parsed) { throw "Not a CMTrace timestamp: date=$Date time=$Time" }
    $value
}

# M-d-yyyy and H:mm:ss as the agent writes them: no leading zero on the month, day or hour is
# required, and the fraction is optional
$script:IslCmTraceTimeFormat = 'M-d-yyyy H:mm:ss.FFFFFFF'
