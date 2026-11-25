function Write-IslTextFile {
    <#
    .SYNOPSIS
    Writes lines to a file below a folder, as UTF-8 without a byte order mark.

    .DESCRIPTION
    One section of the diagnostic package of Export-IntuneAgentDiagnostic, such as the device
    facts or one registry key. The folders on the way to the file are created, and a file that is
    there is replaced. It does not ask ShouldProcess: the command that calls it has asked for the
    whole package, and it writes even when -WhatIf or -Confirm reached it through the preferences.
    A failure ends the function with its error.

    .PARAMETER Root
    The folder the relative path starts from.

    .PARAMETER RelativePath
    The path of the file below the root, such as Registry\Scripts.txt.

    .PARAMETER Line
    The lines of the file. An empty list, or none, writes an empty file.

    .EXAMPLE
    Write-IslTextFile -Root $staging -RelativePath 'Device\system.txt' -Line $system

    Writes the device facts into the staging folder of a package.

    .INPUTS
    None.

    .OUTPUTS
    None.
    #>
    [CmdletBinding()]
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
    # Assigned, not taken from an if expression, which would unroll an empty array to nothing
    [string[]]$text = @()
    if ($null -ne $Line) { $text = $Line }
    try {
        $folder = Split-Path -Path $file -Parent
        $null = New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop @script:IslInternal
        [System.IO.File]::WriteAllLines($file, $text, [System.Text.UTF8Encoding]::new($false))
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
