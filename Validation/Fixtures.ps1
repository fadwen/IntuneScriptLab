# Device-side fixtures for the file, registry and MSI rule experiments (round 5). Delivered by
# Invoke-ValidationRound.ps1 -Action Prepare and run as SYSTEM in the 64-bit host through the guest
# agent. Idempotent; Windows PowerShell 5.1.
#
# What the rules in Experiments.psd1 look for:
#   C:\ProgramData\IntuneScriptLab\Fixtures\present.txt    exists, 7 bytes, modified 2024-06-15T12:00:00Z
#   ...\Fixtures\versioned.exe                             a copy of notepad.exe: file version 10.0.x
#   ...\Fixtures\big.bin                                   exactly 2 MiB
#   %ProgramFiles(x86)%\IntuneScriptLab\x86only.txt        only in the 32-bit Program Files
#   HKLM\SOFTWARE\IntuneScriptLab (64-bit view)            Name (REG_SZ), Build (DWORD 42), BuildText
#                                                          (REG_SZ '42'), Version (REG_SZ '10.0.1'),
#                                                          View (REG_SZ '64'), subkey Only64
#   HKLM\SOFTWARE\WOW6432Node\IntuneScriptLab (32-bit view) View (REG_SZ '32') only
$ErrorActionPreference = 'Stop'

$fixtures = 'C:\ProgramData\IntuneScriptLab\Fixtures'
New-Item -ItemType Directory -Path $fixtures -Force | Out-Null

$present = Join-Path -Path $fixtures -ChildPath 'present.txt'
[IO.File]::WriteAllText($present, 'present')
(Get-Item -Path $present).LastWriteTimeUtc = [datetime]::new(2024, 6, 15, 12, 0, 0, [DateTimeKind]::Utc)

# A real file version (10.0.26100.x) for the "10.0 vs 9.0" string trap
$versioned = Join-Path -Path $fixtures -ChildPath 'versioned.exe'
Copy-Item -Path (Join-Path -Path $env:WINDIR -ChildPath 'System32\notepad.exe') -Destination $versioned -Force

$big = Join-Path -Path $fixtures -ChildPath 'big.bin'
$stream = [IO.File]::Create($big)
try { $stream.SetLength(2MB) } finally { $stream.Dispose() }

$x86Folder = Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'IntuneScriptLab'
New-Item -ItemType Directory -Path $x86Folder -Force | Out-Null
[IO.File]::WriteAllText((Join-Path -Path $x86Folder -ChildPath 'x86only.txt'), 'x86')

$key64 = 'HKLM:\SOFTWARE\IntuneScriptLab'
New-Item -Path $key64 -Force | Out-Null
New-ItemProperty -Path $key64 -Name 'Name' -Value 'IntuneScriptLab' -PropertyType String -Force | Out-Null
New-ItemProperty -Path $key64 -Name 'Build' -Value 42 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $key64 -Name 'BuildText' -Value '42' -PropertyType String -Force | Out-Null
New-ItemProperty -Path $key64 -Name 'Version' -Value '10.0.1' -PropertyType String -Force | Out-Null
New-ItemProperty -Path $key64 -Name 'View' -Value '64' -PropertyType String -Force | Out-Null
New-Item -Path (Join-Path -Path $key64 -ChildPath 'Only64') -Force | Out-Null

$key32 = 'HKLM:\SOFTWARE\WOW6432Node\IntuneScriptLab'
New-Item -Path $key32 -Force | Out-Null
New-ItemProperty -Path $key32 -Name 'View' -Value '32' -PropertyType String -Force | Out-Null

$msi = Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall' |
    Where-Object { $_.PSChildName -match '^\{' } |
    ForEach-Object {
        $p = Get-ItemProperty -Path $_.PSPath
        "$($_.PSChildName) $($p.DisplayName) $($p.DisplayVersion)"
    }

[ordered]@{
    Computer         = $env:COMPUTERNAME
    Is64BitProcess   = [Environment]::Is64BitProcess
    PresentModified  = (Get-Item -Path $present).LastWriteTimeUtc.ToString('o')
    VersionedVersion = (Get-Item -Path $versioned).VersionInfo.FileVersion
    BigBytes         = (Get-Item -Path $big).Length
    View64           = (Get-ItemProperty -Path $key64).View
    View32           = (Get-ItemProperty -Path $key32).View
    MsiProducts      = @($msi)
} | ConvertTo-Json -Compress
