function Compress-IslFolder {
    <#
    .SYNOPSIS
    Writes the files of a folder into a new zip archive, with forward slashes in the entry names.

    .DESCRIPTION
    Windows PowerShell 5.1 runs on .NET Framework, whose ZipFile.CreateFromDirectory writes
    entry names with backslashes, and such an archive does not open as folders on another
    platform. This adds one entry for each file below the folder, named by its path relative to
    the folder with forward slashes, on every host. Empty folders are not kept. The archive must
    not exist yet. The command that calls this has asked ShouldProcess for the whole package,
    and calls it with -WhatIf:$false and -Confirm:$false.

    .PARAMETER Folder
    The full path of the folder to compress, without a trailing separator.

    .PARAMETER Destination
    The full path of the zip archive to create.

    .EXAMPLE
    $entryCount = Compress-IslFolder -Folder $staging -Destination $zip @script:IslInternal

    Writes the staging folder of a diagnostic package into its zip and returns the number of
    entries.

    .INPUTS
    None.

    .OUTPUTS
    System.Int32. The number of entries written.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string]$Folder,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    if (-not $PSCmdlet.ShouldProcess($Destination, "Compress $Folder")) {
        return
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::Open($Destination, 'Create')
    $count = 0
    try {
        foreach ($file in (Get-ChildItem -LiteralPath $Folder -Recurse -File)) {
            $relative = $file.FullName.Substring($Folder.Length).TrimStart('\', '/') -replace '\\', '/'
            $null = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archive, $file.FullName, $relative)
            $count++
        }
    } finally {
        $archive.Dispose()
    }
    $count
}
