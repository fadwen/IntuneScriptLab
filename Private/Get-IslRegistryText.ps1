function Get-IslRegistryText {
    <#
    .SYNOPSIS
    Gets a registry key and its subkeys as lines of text.

    .DESCRIPTION
    For the registry sections of the diagnostic package. Each key is a line "[name]", followed
    by one line "  name = value" for each of its values. The PowerShell provider's own properties
    are left out, binary values are shown by their length, and a value longer than 400
    characters is cut there and marked with "...". A key or a subkey that cannot be read is
    passed over without an error; a key that is not there gives the one line "<key> : not
    present".

    .PARAMETER Key
    The path of the key in a PowerShell registry drive, such as
    HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension.

    .PARAMETER Depth
    How many levels of subkeys below the key are included.

    .EXAMPLE
    Get-IslRegistryText -Key 'HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Policies' -Depth 2

    The policy keys of the agent, two levels down.

    .INPUTS
    None.

    .OUTPUTS
    System.String. One line at a time.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter(Mandatory)]
        [ValidateRange(0, 64)]
        [int]$Depth
    )

    if (-not (Test-Path -LiteralPath $Key)) {
        return "$Key : not present"
    }
    $children = @(Get-ChildItem -LiteralPath $Key -Recurse -Depth $Depth -ErrorAction SilentlyContinue)
    $keys = @(Get-Item -LiteralPath $Key -ErrorAction SilentlyContinue) + $children
    foreach ($item in $keys) {
        "[$($item.Name)]"
        $values = Get-ItemProperty -LiteralPath $item.PSPath -ErrorAction SilentlyContinue
        if (-not $values) { continue }
        foreach ($property in $values.PSObject.Properties) {
            if ($property.Name -like 'PS*') { continue }
            $text = if ($property.Value -is [byte[]]) { "byte[$($property.Value.Length)]" }
            else { "$($property.Value)" }
            if ($text.Length -gt 400) { $text = $text.Substring(0, 400) + '...' }
            "  $($property.Name) = $text"
        }
    }
}
