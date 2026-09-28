function Get-IslOemEncoding {
    <#
    .SYNOPSIS
        The OEM code page encoding a console-less powershell.exe writes its output in.

    .DESCRIPTION
        Windows PowerShell's [Console]::OutputEncoding defaults to the system OEM code page
        (437 on US systems), which is what turned "Grüße — ✓" into "Grüße - √" in Intune's
        reports. Read it from the registry rather than CultureInfo, which lies under invariant
        globalization, and register the legacy code pages when running on .NET Core.
    #>
    [CmdletBinding()]
    [OutputType([System.Text.Encoding])]
    param()

    $codePage = 437
    try {
        $key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage'
        $value = (Get-ItemProperty -Path $key -Name OEMCP -ErrorAction Stop).OEMCP
        if ($value -match '^\d+$') { $codePage = [int]$value }
    }
    catch { Write-Verbose "OEMCP not readable from the registry, assuming $codePage" }

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
