function ConvertTo-IslSarifLocation {
    <#
    .SYNOPSIS
    Converts a script path to the artifactLocation of a SARIF result.

    .DESCRIPTION
    A path below the root becomes a relative URI with the base %SRCROOT%, so that a code
    scanning service shows the finding against the file in the repository. Each segment is
    escaped as a URI segment, and the separators become forward slashes. A path outside the root
    becomes an absolute file URI with no base. The comparison of the path with the root ignores
    letter case, as Windows paths do.

    .PARAMETER FilePath
    The full path of the script that a finding is about.

    .PARAMETER RootPath
    The full path of the folder the relative URIs start from, without a trailing separator.

    .EXAMPLE
    ConvertTo-IslSarifLocation -FilePath 'C:\repo\Remediations\A\Detect.ps1' -RootPath 'C:\repo'

    Returns @{ uri = 'Remediations/A/Detect.ps1'; uriBaseId = '%SRCROOT%' }.

    .INPUTS
    None.

    .OUTPUTS
    System.Collections.Specialized.OrderedDictionary. The uri, and uriBaseId for a path below
    the root.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$RootPath
    )

    if ($FilePath.StartsWith($RootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relative = $FilePath.Substring($RootPath.Length).TrimStart('\', '/')
        $segments = foreach ($segment in $relative -split '[\\/]') { [System.Uri]::EscapeDataString($segment) }
        return [ordered]@{ uri = ($segments -join '/'); uriBaseId = '%SRCROOT%' }
    }
    # Outside the root: an absolute file URI, with no base to resolve against
    [ordered]@{ uri = ([System.Uri]::new($FilePath)).AbsoluteUri }
}
