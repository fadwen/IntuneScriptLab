function Stop-IslProcessTree {
    <#
    .SYNOPSIS
    Ends a process and every process it started.

    .DESCRIPTION
    The cleanup after a run that timed out. taskkill.exe ends the tree, and it is started as a
    process whose streams .NET redirects, not with the call operator: Windows PowerShell 5.1
    turns a line that a native command writes to a redirected error stream into an error record,
    and with an error preference of Stop in the caller's scope that record ends the command. A
    process that is already gone is such a line ("The process ... not found", exit code 128), and
    it is the state the cleanup wants.

    Nothing is reported when taskkill succeeds or finds no such process. When it fails for
    another reason and the process is still there, a warning says so, because then the run left
    something behind.

    .PARAMETER ProcessId
    The id of the process at the root of the tree.

    .EXAMPLE
    Stop-IslProcessTree -ProcessId $process.Id -Confirm:$false

    Ends the process a run started, and what that process started, after the run timed out.

    .EXAMPLE
    Stop-IslProcessTree -ProcessId 4711 -WhatIf

    Says which process tree would be ended, and ends nothing.

    .INPUTS
    None.

    .OUTPUTS
    None.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [int]$ProcessId
    )

    if (-not $PSCmdlet.ShouldProcess("process $ProcessId and the processes it started", 'End')) {
        return
    }

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = Join-Path -Path ([System.Environment]::SystemDirectory) -ChildPath 'taskkill.exe'
    $startInfo.Arguments = "/PID $ProcessId /T /F"
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $taskkill = [System.Diagnostics.Process]::new()
    $taskkill.StartInfo = $startInfo
    try {
        $null = $taskkill.Start()
        # Both streams are read while the process runs, so that neither fills and blocks it
        $outputTask = $taskkill.StandardOutput.ReadToEndAsync()
        $errorTask = $taskkill.StandardError.ReadToEndAsync()
        $taskkill.WaitForExit()
        $exitCode = $taskkill.ExitCode
        $null = $outputTask.GetAwaiter().GetResult()
        $errorText = "$($errorTask.GetAwaiter().GetResult())".Trim()
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    } finally {
        $taskkill.Dispose()
    }

    Write-Verbose "taskkill.exe /PID $ProcessId /T /F ended with exit code $exitCode. $errorText"
    # 0 is success and 128 is "no such process". After any other answer the process itself decides:
    # taskkill also fails when a child ended between its listing of the tree and its attempt
    if ($exitCode -notin 0, 128) {
        $survivor = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if ($null -ne $survivor) {
            Write-Warning ("Process $ProcessId is still running: taskkill.exe ended with exit code " +
                "${exitCode}. $errorText")
        }
    }
}
