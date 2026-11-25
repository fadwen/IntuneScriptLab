function ConvertTo-IslScriptText {
    <#
    .SYNOPSIS
    Reads a script's bytes as UTF-8 text and tells whether they have a BOM.

    .DESCRIPTION
    For Compare-IntuneDeployedScript. The UTF-8 byte order mark, EF BB BF, is left out of the
    text and reported in Bom, so that a script that differs only in its byte order mark can be
    told apart from one whose content differs.

    .PARAMETER Bytes
    The script's bytes.

    .EXAMPLE
    ConvertTo-IslScriptText -Bytes ([System.IO.File]::ReadAllBytes($path))

    Bom $true and the text after the mark for a file saved as UTF-8 with a BOM.

    .INPUTS
    None.

    .OUTPUTS
    IntuneScriptLab.ScriptText. An object with Bom and Text.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.ScriptText')]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [byte[]]$Bytes
    )

    $bom = $Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF
    $start = if ($bom) { 3 } else { 0 }
    [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.ScriptText'
        Bom = $bom
        Text = [System.Text.Encoding]::UTF8.GetString($Bytes, $start, $Bytes.Length - $start)
    }
}
