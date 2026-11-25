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

    .INPUTS
        None.

    .OUTPUTS
        System.Object. One object for each row of the report, with its columns as properties.
    #>
    [CmdletBinding()]
    [OutputType([object])]
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
    $zipName = "IntuneScriptLab-$([guid]::NewGuid().ToString('N')).zip"
    $zip = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath $zipName
    $invalidResult = [System.Management.Automation.ErrorCategory]::InvalidResult
    # The job, the wait for it, the download and the read are one transaction: a step that fails
    # ends the function, and the records raised in here pass through the catch unchanged
    try {
        $job = Invoke-IslGraphRequest -Uri $jobs -Method POST -Body $body
        $jobStatus = "$(Get-IslPropertyValue -InputObject $job -Name 'status')"
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while ($jobStatus -in 'notStarted', 'inProgress') {
            if ((Get-Date) -gt $deadline) {
                $recordSplat = @{
                    Message = "The $ReportName export job did not complete within $TimeoutSeconds seconds"
                    ErrorId = 'ExportJobTimedOut'
                    Category = [System.Management.Automation.ErrorCategory]::OperationTimeout
                    TargetObject = $ReportName
                    ExceptionType = [System.TimeoutException]
                }
                $PSCmdlet.ThrowTerminatingError((New-IslErrorRecord @recordSplat))
            }
            Start-Sleep -Seconds 5
            $jobId = Get-IslPropertyValue -InputObject $job -Name 'id'
            $job = Invoke-IslGraphRequest -Uri "$jobs/$jobId"
            $jobStatus = "$(Get-IslPropertyValue -InputObject $job -Name 'status')"
        }
        # The download address is there only once the job has completed
        $jobUrl = Get-IslPropertyValue -InputObject $job -Name 'url'
        if ($jobStatus -ne 'completed' -or -not $jobUrl) {
            $message = "The $ReportName export job ended with status '$jobStatus'"
            $recordSplat = @{ Message = $message; ErrorId = 'ExportJobFailed'; Category = $invalidResult }
            $PSCmdlet.ThrowTerminatingError((New-IslErrorRecord @recordSplat -TargetObject $ReportName))
        }

        Invoke-WebRequest -Uri $jobUrl -OutFile $zip -UseBasicParsing -ErrorAction Stop
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
        try {
            $entry = $archive.Entries | Where-Object Name -like '*.csv' | Select-Object -First 1
            if (-not $entry) {
                $message = "The $ReportName export contains no CSV file"
                $recordSplat = @{ Message = $message; ErrorId = 'ExportHasNoCsv'; Category = $invalidResult }
                $PSCmdlet.ThrowTerminatingError((New-IslErrorRecord @recordSplat -TargetObject $ReportName))
            }
            $reader = [System.IO.StreamReader]::new($entry.Open())
            try { $csv = $reader.ReadToEnd() } finally { $reader.Dispose() }
        }
        finally { $archive.Dispose() }
        $rows = @($csv | ConvertFrom-Csv)
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    } finally {
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue @script:IslInternal
    }

    $rows
}
