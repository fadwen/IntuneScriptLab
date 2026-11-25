function Assert-IslTextLength {
    <#
    .SYNOPSIS
        Ends the caller when a text parameter holds a value longer than its limit.

    .DESCRIPTION
        For the commands whose -Name, -Id, -IncludeRule and -ExcludeRule take text that names or
        identifies something. A [ValidateLength()] attribute would also refuse $null and a
        collection with a $null element, which those parameters take to mean "not given", so the
        length is checked in the body instead: $null and empty values pass, and the first value
        longer than the limit ends the function with InputTooLong.

    .PARAMETER Name
        The parameter's name, without the dash, for the message.

    .PARAMETER Value
        The parameter's value: nothing, one string or several.

    .PARAMETER Maximum
        The longest value allowed, 1,000 characters by default.

    .EXAMPLE
        Assert-IslTextLength -Name 'Id' -Value $Id

        Returns nothing when every id is at most 1,000 characters long, and ends the function
        otherwise.

    .INPUTS
        None.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Value,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Maximum = 1000
    )

    foreach ($item in @($Value)) {
        if ($null -eq $item) {
            continue
        }
        $length = "$item".Length
        if ($length -gt $Maximum) {
            $recordSplat = @{
                Message = "-$Name holds a value of $length characters; it takes at most $Maximum"
                ErrorId = 'InputTooLong'
                Category = 'InvalidArgument'
                TargetObject = $Name
            }
            $PSCmdlet.ThrowTerminatingError((New-IslErrorRecord @recordSplat))
        }
    }
}
