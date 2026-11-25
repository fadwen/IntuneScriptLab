function Get-IslContentHash {
    <#
    .SYNOPSIS
    Gets the SHA-256 hash of a script's bytes as lower-case hex.

    .DESCRIPTION
    For Compare-IntuneDeployedScript, which tells an unchanged script from a drifted one by
    comparing the hash of the local file with that of the tenant's copy, byte for byte.

    .PARAMETER Bytes
    The script's bytes. An empty array gives the hash of no bytes.

    .EXAMPLE
    Get-IslContentHash -Bytes ([System.IO.File]::ReadAllBytes($path))

    The 64 hex characters of the file's SHA-256 hash.

    .INPUTS
    None.

    .OUTPUTS
    System.String.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [byte[]]$Bytes
    )

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($Bytes)
    } finally {
        $sha.Dispose()
    }
    ([System.BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
}
