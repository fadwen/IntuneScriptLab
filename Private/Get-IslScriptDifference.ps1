function Get-IslScriptDifference {
    <#
    .SYNOPSIS
    Describes how two scripts that are not byte-identical differ.

    .DESCRIPTION
    For Compare-IntuneDeployedScript, once the hashes of the local file and the tenant's copy
    differ. Each difference is named and described:

    - Bom: one has a UTF-8 byte order mark and the other has none.
    - LineEndings: both have line endings, CRLF on one side and LF on the other.
    - Content: the lines differ once trailing white space and blank lines at the end are left
      out. The detail names the first differing line, quotes it on both sides, and counts the
      lines that only one side has.
    - Whitespace: only trailing white space or blank lines at the end differ.

    Bytes that differ although the UTF-8 text is the same count as Content.

    .PARAMETER Local
    The local file's bytes.

    .PARAMETER Tenant
    The tenant's bytes, decoded from base64.

    .EXAMPLE
    Get-IslScriptDifference -Local $localBytes -Tenant $tenantBytes

    Differences Bom and Detail "the local file has a BOM, the tenant's has none" for two copies
    that differ only in the mark.

    .INPUTS
    None.

    .OUTPUTS
    IntuneScriptLab.ScriptDifference. An object with Differences and Detail.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.ScriptDifference')]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [byte[]]$Local,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [byte[]]$Tenant
    )

    $differences = [System.Collections.Generic.List[string]]::new()
    $details = [System.Collections.Generic.List[string]]::new()
    $localText = ConvertTo-IslScriptText -Bytes $Local
    $tenantText = ConvertTo-IslScriptText -Bytes $Tenant
    if ($localText.Bom -ne $tenantText.Bom) {
        $differences.Add('Bom')
        $localBom = if ($localText.Bom) { 'has a BOM' } else { 'has no BOM' }
        $tenantBom = if ($tenantText.Bom) { 'has one' } else { 'has none' }
        $details.Add("the local file $localBom, the tenant's $tenantBom")
    }
    $localEol = Get-IslLineEnding -Text $localText.Text
    $tenantEol = Get-IslLineEnding -Text $tenantText.Text
    if ($localEol -and $tenantEol -and $localEol -ne $tenantEol) {
        $differences.Add('LineEndings')
        $details.Add("line endings $localEol locally, $tenantEol in the tenant")
    }
    $localLines = @($localText.Text -split "`r?`n")
    $tenantLines = @($tenantText.Text -split "`r?`n")
    # A single line comes back from the pipeline as a string, which has no Count under strict mode
    $localTrim = @(Get-IslTrimmedLine -Line @($localLines | ForEach-Object { $_.TrimEnd() }))
    $tenantTrim = @(Get-IslTrimmedLine -Line @($tenantLines | ForEach-Object { $_.TrimEnd() }))
    if (($localTrim -join "`n") -cne ($tenantTrim -join "`n")) {
        $differences.Add('Content')
        $line = 0
        $limit = [Math]::Min($localTrim.Count, $tenantTrim.Count)
        while ($line -lt $limit -and $localTrim[$line] -ceq $tenantTrim[$line]) { $line++ }
        $localExcerpt = '<end>'
        if ($line -lt $localTrim.Count) { $localExcerpt = Get-IslLineExcerpt -Line $localTrim[$line] }
        $tenantExcerpt = '<end>'
        if ($line -lt $tenantTrim.Count) { $tenantExcerpt = Get-IslLineExcerpt -Line $tenantTrim[$line] }
        $compareSplat = @{ ReferenceObject = $localTrim; DifferenceObject = $tenantTrim; CaseSensitive = $true }
        $compared = @(Compare-Object @compareSplat)
        $onlyLocal = @($compared | Where-Object SideIndicator -EQ '<=').Count
        $onlyTenant = @($compared | Where-Object SideIndicator -EQ '=>').Count
        $details.Add(("content differs from line $($line + 1): local '$localExcerpt', tenant " +
                "'$tenantExcerpt' ($onlyLocal line(s) only local, $onlyTenant only in the tenant)"))
    } elseif (($localLines -join "`n") -cne ($tenantLines -join "`n")) {
        $differences.Add('Whitespace')
        $details.Add('only trailing whitespace or blank lines at the end differ')
    }
    if ($differences.Count -eq 0) {
        $differences.Add('Content')
        $details.Add('the bytes differ outside the UTF-8 text')
    }
    [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.ScriptDifference'
        Differences = $differences.ToArray()
        Detail = ($details -join '; ')
    }
}
