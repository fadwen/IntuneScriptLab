function Get-IslIntuneOutput {
    <#
    .SYNOPSIS
        Reduces a script's captured output to what Intune would show for a remediation.

    .DESCRIPTION
        Observed (REM-OUT-STREAMS, REM-OUT-LONG, REM-ERR-LONG): the report holds only the last
        line of stdout, and only the last 2,048 characters of it; the error field holds the
        whole stderr text, also capped at its last 2,048 characters.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.IntuneOutput')]
    param(
        [AllowEmptyString()]
        [string]$StdOut = '',

        [AllowEmptyString()]
        [string]$StdErr = '',

        [int]$Limit = 2048
    )

    $lines = @($StdOut -split "`r?`n" | Where-Object { $_ -ne '' })
    $lastLine = if ($lines.Count -gt 0) { $lines[-1] } else { '' }
    $outputTruncated = $lastLine.Length -gt $Limit
    if ($outputTruncated) { $lastLine = $lastLine.Substring($lastLine.Length - $Limit) }

    $errorText = $StdErr.TrimEnd("`r", "`n")
    $errorTruncated = $errorText.Length -gt $Limit
    if ($errorTruncated) { $errorText = $errorText.Substring($errorText.Length - $Limit) }

    [pscustomobject]@{
        PSTypeName      = 'IntuneScriptLab.IntuneOutput'
        Output          = $lastLine
        Error           = $errorText
        DroppedLines    = [Math]::Max(0, $lines.Count - 1)
        OutputTruncated = $outputTruncated
        ErrorTruncated  = $errorTruncated
    }
}
