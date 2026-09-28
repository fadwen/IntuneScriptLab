# Shared probe header, prepended to every experiment script before upload.
# Must stay Windows PowerShell 5.1 compatible: this is what runs on the device.
# Records how the Intune Management Extension actually launched the script,
# independent of what Intune later reports back.

function Write-ProbeRecord {
    param(
        [Parameter(Mandatory)][string]$Experiment,
        [Parameter(Mandatory)][string]$Phase
    )

    $dir = 'C:\ProgramData\IntuneScriptLab'
    if (-not (Test-Path -Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $proc = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$PID"
    $parent = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$($proc.ParentProcessId)"

    $firstBytes = ''
    $sha256 = ''
    if ($PSCommandPath -and (Test-Path -Path $PSCommandPath)) {
        $bytes = [IO.File]::ReadAllBytes($PSCommandPath)
        $firstBytes = ($bytes[0..3] | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
        $sha256 = (Get-FileHash -Path $PSCommandPath -Algorithm SHA256).Hash
    }

    $record = [ordered]@{
        Experiment        = $Experiment
        Phase             = $Phase
        Time              = (Get-Date).ToUniversalTime().ToString('o')
        User              = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        Is64BitProcess    = [Environment]::Is64BitProcess
        PSVersion         = $PSVersionTable.PSVersion.ToString()
        PSEdition         = "$($PSVersionTable.PSEdition)"
        PSHome            = $PSHOME
        CommandLine       = $proc.CommandLine
        ParentName        = $parent.Name
        ParentCommandLine = $parent.CommandLine
        SessionId         = $proc.SessionId
        UserInteractive   = [Environment]::UserInteractive
        ScriptPath        = $PSCommandPath
        ScriptFirstBytes  = $firstBytes
        ScriptSha256      = $sha256
        Cwd               = (Get-Location).Path
        LanguageMode      = "$($ExecutionContext.SessionState.LanguageMode)"
        ExecutionPolicy   = "$(Get-ExecutionPolicy)"
        Temp              = $env:TEMP
        UserProfile       = $env:USERPROFILE
        AppData           = $env:APPDATA
        ConsoleEncoding   = [Console]::OutputEncoding.WebName
        OutputEncoding    = $OutputEncoding.WebName
        Culture           = (Get-Culture).Name
        # Non-ASCII literal: arrives intact only if the script file was decoded as UTF-8
        NonAscii          = 'Grüße — ✓'
    }

    $line = $record | ConvertTo-Json -Compress
    Add-Content -Path (Join-Path -Path $dir -ChildPath "$Experiment.jsonl") -Value $line -Encoding UTF8
}

function Write-EspState {
    # Round 8: what the Enrollment Status Page was doing when a script ran. The FirstSync values
    # under the enrollment key are the ESP's own bookkeeping; the tracking key counts the apps it
    # is watching; a logged-on user and a running explorer mark the end of the device phase.
    param(
        [Parameter(Mandatory)][string]$Experiment,
        [Parameter(Mandatory)][string]$Phase
    )

    $dir = 'C:\ProgramData\IntuneScriptLab'
    if (-not (Test-Path -Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $enrollments = Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue
    $firstSync = foreach ($enrollment in $enrollments) {
        $syncPath = Join-Path -Path $enrollment.PSPath -ChildPath 'FirstSync'
        $sync = Get-ItemProperty -Path $syncPath -ErrorAction SilentlyContinue
        if (-not $sync) { continue }
        $values = $sync.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } |
            ForEach-Object { "$($_.Name)=$($_.Value)" }
        "$($enrollment.PSChildName): $($values -join ';')"
    }
    $trackingKey = 'HKLM:\SOFTWARE\Microsoft\Windows\Autopilot\EnrollmentStatusTracking'
    $tracked = @(Get-ChildItem -Path $trackingKey -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -like 'Win32App_*' } |
        ForEach-Object { "$($_.PSChildName)=$((Get-ItemProperty -Path $_.PSPath).InstallationState)" })
    $record = [ordered]@{
        Experiment     = $Experiment
        Phase          = $Phase
        Time           = (Get-Date).ToUniversalTime().ToString('o')
        User           = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        OobeInProgress = (Get-ItemProperty -Path 'HKLM:\SYSTEM\Setup' -ErrorAction SilentlyContinue).OOBEInProgress
        Sessions       = @(query user 2>$null | Select-Object -Skip 1 | ForEach-Object { $_.Trim() })
        Explorer       = [bool](Get-Process -Name explorer -ErrorAction SilentlyContinue)
        FirstSync      = @($firstSync)
        TrackedApps    = $tracked
    }
    $line = $record | ConvertTo-Json -Compress
    Add-Content -Path (Join-Path -Path $dir -ChildPath 'esp-state.jsonl') -Value $line -Encoding UTF8
}
