function Invoke-IslNativeCommand {
    <#
    .SYNOPSIS
    Runs a Windows executable to its end and returns its exit code and what it wrote.

    .DESCRIPTION
    For the small system tools the module calls for a side effect, such as taskkill.exe and
    icacls.exe, whose error text is needed when they fail. The executable is started as a process
    whose streams .NET redirects, not with the call operator: Windows PowerShell 5.1 turns a line
    that a native command writes to a redirected error stream into an error record, and with an
    error preference of Stop in the caller's scope the first such line ends the caller.

    The exit code is returned, not judged. What a code means differs from tool to tool, so the
    caller decides.

    .PARAMETER FilePath
    The full path of the executable.

    .PARAMETER Arguments
    The arguments, as one string in the form the executable parses. An argument that can hold a
    space is quoted by the caller.

    .EXAMPLE
    $taskkill = Join-Path -Path ([System.Environment]::SystemDirectory) -ChildPath 'taskkill.exe'
    $result = Invoke-IslNativeCommand -FilePath $taskkill -Arguments '/PID 4711 /T /F'

    Ends process 4711 and what it started. $result.ExitCode is 128 when there is no such process.

    .INPUTS
    None.

    .OUTPUTS
    IntuneScriptLab.NativeCommandResult. ExitCode, StdOut and StdErr.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.NativeCommandResult')]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter()]
        [string]$Arguments = ''
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = $Arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        $null = $process.Start()
        # Both streams are read while the process runs, so that neither fills and blocks it
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $exitCode = $process.ExitCode
        $outputText = "$($outputTask.GetAwaiter().GetResult())".Trim()
        $errorText = "$($errorTask.GetAwaiter().GetResult())".Trim()
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    } finally {
        $process.Dispose()
    }

    [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.NativeCommandResult'
        ExitCode = $exitCode
        StdOut = $outputText
        StdErr = $errorText
    }
}
