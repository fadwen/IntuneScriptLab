function ConvertTo-IslNameKey {
    <#
    .SYNOPSIS
    Turns a policy, folder or file name into the key local scripts match by.

    .DESCRIPTION
    For Compare-IntuneDeployedScript, which pairs a tenant policy with a local folder or file of
    the same name. Every character that is not a letter, digit, underscore, dot or hyphen becomes
    an underscore, and the result is lower case, so that "Detect Printer" matches a folder named
    detect_printer or Detect_Printer.

    .PARAMETER Value
    The name.

    .EXAMPLE
    ConvertTo-IslNameKey -Value 'Detect Printer (x64)'

    Returns 'detect_printer__x64_'.

    .INPUTS
    None.

    .OUTPUTS
    System.String.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value
    )

    ([regex]::Replace($Value, '[^\w.-]', '_')).ToLowerInvariant()
}
