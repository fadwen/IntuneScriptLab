function Copy-IslSharedFile {
    <#
    .SYNOPSIS
    Copies a file that another process holds open for writing.

    .DESCRIPTION
    The agent keeps its current log open while it writes to it. A stream that allows only
    other readers cannot open such a file, so the source is opened for reading with write
    sharing allowed, and the copy is the file as it stands at that moment. A file that is at the
    destination is replaced. The command that calls this has asked ShouldProcess for the whole
    package, and calls it with -WhatIf:$false and -Confirm:$false.

    .PARAMETER Source
    The full path of the file to copy.

    .PARAMETER Destination
    The full path of the copy. Its folder must exist.

    .EXAMPLE
    Copy-IslSharedFile -Source $log.FullName -Destination $copy @script:IslInternal

    Copies a log of the agent that the agent is still writing.

    .INPUTS
    None.

    .OUTPUTS
    None.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    if (-not $PSCmdlet.ShouldProcess($Destination, "Copy $Source")) {
        return
    }
    $in = [System.IO.File]::Open($Source, 'Open', 'Read', 'ReadWrite')
    try {
        $out = [System.IO.File]::Create($Destination)
        try { $in.CopyTo($out) } finally { $out.Dispose() }
    } finally {
        $in.Dispose()
    }
}
