function Get-IslExportReport {
    <#
    .SYNOPSIS
        Runs one Intune report export job and returns its rows.

    .DESCRIPTION
        The per-app status endpoints (installSummary, deviceStatuses, userStatuses) are gone from
        Graph (Findings.md, "Install status via Graph"); the export jobs under
        deviceManagement/reports are what works. This posts one job, polls it every five seconds
        until it completes, downloads the zipped CSV it produces and returns the rows as objects.
        AppInstallStatusAggregate gives every app's install counts in one job of about twenty
        seconds; DeviceInstallStatusByApp needs an ApplicationId filter and one job per app.

    .PARAMETER ReportName
        The report to export, e.g. AppInstallStatusAggregate.

    .PARAMETER Filter
        The report's filter expression, when it needs one.

    .PARAMETER Select
        The columns to export; all of them when omitted.

    .PARAMETER TimeoutSeconds
        How long to wait for the job. Default 300.

    .EXAMPLE
        Get-IslExportReport -ReportName AppInstallStatusAggregate

        One row per app with InstalledDeviceCount, FailedDeviceCount and the other counts.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$ReportName,

        [string]$Filter,

        [string[]]$Select,

        [int]$TimeoutSeconds = 300
    )

    $body = @{ reportName = $ReportName; format = 'csv' }
    if ($Filter) { $body.filter = $Filter }
    if ($Select) { $body.select = $Select }
    $jobs = '/beta/deviceManagement/reports/exportJobs'
    $job = Invoke-IslGraphRequest -Uri $jobs -Method POST -Body $body
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ("$($job.status)" -in 'notStarted', 'inProgress') {
        if ((Get-Date) -gt $deadline) {
            throw "The $ReportName export job did not complete within $TimeoutSeconds seconds"
        }
        Start-Sleep -Seconds 5
        $job = Invoke-IslGraphRequest -Uri "$jobs/$($job.id)"
    }
    if ("$($job.status)" -ne 'completed' -or -not $job.url) {
        throw "The $ReportName export job ended with status '$($job.status)'"
    }

    $zipName = "IntuneScriptLab-$([guid]::NewGuid().ToString('N')).zip"
    $zip = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath $zipName
    try {
        Invoke-WebRequest -Uri $job.url -OutFile $zip -UseBasicParsing
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
        try {
            $entry = $archive.Entries | Where-Object Name -like '*.csv' | Select-Object -First 1
            if (-not $entry) { throw "The $ReportName export contains no CSV file" }
            $reader = [System.IO.StreamReader]::new($entry.Open())
            try { $csv = $reader.ReadToEnd() } finally { $reader.Dispose() }
        }
        finally { $archive.Dispose() }
        @($csv | ConvertFrom-Csv)
    }
    finally {
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
    }
}
