function Write-IslTextFile {
    <#
    .SYNOPSIS
    Writes lines to a file below a folder, as UTF-8 without a byte order mark.

    .DESCRIPTION
    One section of the diagnostic package of Export-IntuneAgentDiagnostic, such as the device
    facts or one registry key. The folders on the way to the file are created, and a file that is
    there is replaced. The command that calls this has asked ShouldProcess for the whole package,
    and calls it with -WhatIf:$false and -Confirm:$false.

    .PARAMETER Root
    The folder the relative path starts from.

    .PARAMETER RelativePath
    The path of the file below the root, such as Registry\Scripts.txt.

    .PARAMETER Line
    The lines of the file. An empty list, or none, writes an empty file.

    .EXAMPLE
    Write-IslTextFile -Root $staging -RelativePath 'Device\system.txt' -Line $system @script:IslInternal

    Writes the device facts into the staging folder of a package.

    .INPUTS
    None.

    .OUTPUTS
    None.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$Root,

        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Line
    )

    $file = Join-Path -Path $Root -ChildPath $RelativePath
    if (-not $PSCmdlet.ShouldProcess($file, 'Write the file')) {
        return
    }
    $folder = Split-Path -Path $file -Parent
    $null = New-Item -ItemType Directory -Path $folder -Force @script:IslInternal
    # Assigned, not taken from an if expression, which would unroll an empty array to nothing
    [string[]]$text = @()
    if ($null -ne $Line) { $text = $Line }
    [System.IO.File]::WriteAllLines($file, $text, [System.Text.UTF8Encoding]::new($false))
}
