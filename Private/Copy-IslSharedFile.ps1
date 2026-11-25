function Copy-IslSharedFile {
    <#
    .SYNOPSIS
    Copies a file that another process holds open for writing.

    .DESCRIPTION
    The agent keeps its current log open while it writes to it. A stream that allows only
    other readers cannot open such a file, so the source is opened for reading with write
    sharing allowed, and the copy is the file as it stands at that moment. A file that is at the
    destination is replaced. It does not ask ShouldProcess: the command that calls it has asked
    for the whole package, and it copies even when -WhatIf or -Confirm reached it through the
    preferences. A failure ends the function with its error.

    .PARAMETER Source
    The full path of the file to copy.

    .PARAMETER Destination
    The full path of the copy. Its folder must exist.

    .EXAMPLE
    Copy-IslSharedFile -Source $log.FullName -Destination $copy

    Copies a log of the agent that the agent is still writing.

    .INPUTS
    None.

    .OUTPUTS
    None.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    $in = $null
    $out = $null
    try {
        $in = [System.IO.File]::Open($Source, 'Open', 'Read', 'ReadWrite')
        $out = [System.IO.File]::Create($Destination)
        $in.CopyTo($out)
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    } finally {
        if ($null -ne $out) { $out.Dispose() }
        if ($null -ne $in) { $in.Dispose() }
    }
}
