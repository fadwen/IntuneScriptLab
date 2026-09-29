function Get-IslOemEncoding {
    <#
    .SYNOPSIS
        The OEM code page encoding a console-less powershell.exe writes its output in.

    .DESCRIPTION
        Windows PowerShell's [Console]::OutputEncoding defaults to the system OEM code page
        (437 on US systems), which is what turned "Grüße — ✓" into "Grüße - √" in Intune's
        reports. Read it from the registry rather than CultureInfo, which lies under invariant
        globalization, and register the legacy code pages when running on .NET Core.

    .PARAMETER Kind
        OEM (the default) is what a console-less powershell.exe writes its output in; ANSI is
        what Windows PowerShell 5.1 reads a file without a BOM as.
    #>
    [CmdletBinding()]
    [OutputType([System.Text.Encoding])]
    param(
        [ValidateSet('OEM', 'ANSI')]
        [string]$Kind = 'OEM'
    )

    $valueName = if ($Kind -eq 'ANSI') { 'ACP' } else { 'OEMCP' }
    $codePage = if ($Kind -eq 'ANSI') { 1252 } else { 437 }
    try {
        $key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage'
        $value = (Get-ItemProperty -Path $key -Name $valueName -ErrorAction Stop).$valueName
        if ($value -match '^\d+$') { $codePage = [int]$value }
    }
    catch { Write-Verbose "$valueName not readable from the registry, assuming $codePage" }

    try {
        if (-not ('System.Text.CodePagesEncodingProvider' -as [type])) { throw 'no provider type' }
        [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance)
    }
    catch { Write-Verbose 'Code page provider not registered (Windows PowerShell has the code pages built in)' }

    try { [System.Text.Encoding]::GetEncoding($codePage) }
    catch {
        Write-Verbose "Code page $codePage unavailable; falling back to the console encoding"
        [Console]::OutputEncoding
    }
}
