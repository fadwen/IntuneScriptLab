function Compress-IslFolder {
    <#
    .SYNOPSIS
    Writes the files of a folder into a new zip archive, with forward slashes in the entry names.

    .DESCRIPTION
    Windows PowerShell 5.1 runs on .NET Framework, whose ZipFile.CreateFromDirectory writes
    entry names with backslashes, and such an archive does not open as folders on another
    platform. This adds one entry for each file below the folder, named by its path relative to
    the folder with forward slashes, on every host. Empty folders are not kept. The archive must
    not exist yet. It does not ask ShouldProcess: the command that calls it has asked for the
    whole package, and it writes even when -WhatIf or -Confirm reached it through the
    preferences. A failure ends the function with its error.

    .PARAMETER Folder
    The full path of the folder to compress, without a trailing separator.

    .PARAMETER Destination
    The full path of the zip archive to create.

    .EXAMPLE
    $entryCount = Compress-IslFolder -Folder $staging -Destination $zip

    Writes the staging folder of a diagnostic package into its zip and returns the number of
    entries.

    .INPUTS
    None.

    .OUTPUTS
    System.Int32. The number of entries written.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string]$Folder,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    $archive = $null
    $count = 0
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
        $files = @(Get-ChildItem -LiteralPath $Folder -Recurse -File -ErrorAction Stop)
        $archive = [System.IO.Compression.ZipFile]::Open($Destination, 'Create')
        foreach ($file in $files) {
            $relative = $file.FullName.Substring($Folder.Length).TrimStart('\', '/') -replace '\\', '/'
            $null = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archive, $file.FullName, $relative)
            $count++
        }
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    } finally {
        if ($null -ne $archive) { $archive.Dispose() }
    }
    $count
}
