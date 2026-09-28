#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The export job seam: a job is posted, polled until it completes, its zipped CSV downloaded and
    read as rows; a job that ends in failure or never completes is a terminating error.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    # Writes a zip holding one CSV to the path Invoke-WebRequest was told to save to
    function script:Write-FakeExport {
        param([string]$OutFile, [string]$Csv)
        $archive = [System.IO.Compression.ZipFile]::Open($OutFile, 'Create')
        try {
            $entry = $archive.CreateEntry('AppInstallStatusAggregate.csv')
            $writer = [System.IO.StreamWriter]::new($entry.Open())
            try { $writer.Write($Csv) } finally { $writer.Dispose() }
        }
        finally { $archive.Dispose() }
    }
    $script:Csv = "ApplicationId,DisplayName,InstalledDeviceCount,FailedDeviceCount`r`n" +
        "app-a,Widget 2.0,4,1`r`napp-b,Widget 1.0,0,0`r`n"
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Get-IslExportReport' -Tag 'Unit', 'Private' {

    BeforeEach {
        Mock Start-Sleep -ModuleName IntuneScriptLab { }
        Mock Invoke-WebRequest -ModuleName IntuneScriptLab {
            Write-FakeExport -OutFile $OutFile -Csv $script:Csv
        }
    }

    It 'posts the job, polls it and returns the CSV rows of the download' {
        $script:Polls = 0
        Mock Invoke-IslGraphRequest -ModuleName IntuneScriptLab {
            if ($Method -eq 'POST') { return @{ id = 'job-1'; status = 'notStarted' } }
            $script:Polls++
            if ($script:Polls -lt 2) { return @{ id = 'job-1'; status = 'inProgress' } }
            @{ id = 'job-1'; status = 'completed'; url = 'https://download.example/job-1.zip' }
        }
        $rows = InModuleScope IntuneScriptLab { Get-IslExportReport -ReportName 'AppInstallStatusAggregate' }
        @($rows).Count | Should-Be 2
        $rows[0].ApplicationId | Should-Be 'app-a'
        $rows[0].InstalledDeviceCount | Should-Be '4'
        Should-Invoke Invoke-IslGraphRequest -ModuleName IntuneScriptLab -ParameterFilter {
            $Method -eq 'POST' -and $Body.reportName -eq 'AppInstallStatusAggregate' -and $Body.format -eq 'csv'
        } -Times 1 -Exactly
        Should-Invoke Invoke-IslGraphRequest -ModuleName IntuneScriptLab -ParameterFilter {
            $Uri -like '*/exportJobs/job-1'
        } -Times 2 -Exactly
        Should-Invoke Invoke-WebRequest -ModuleName IntuneScriptLab -ParameterFilter {
            $Uri -eq 'https://download.example/job-1.zip'
        } -Times 1 -Exactly
    }

    It 'passes a filter and a column list through to the job' {
        Mock Invoke-IslGraphRequest -ModuleName IntuneScriptLab {
            @{ id = 'job-2'; status = 'completed'; url = 'https://download.example/job-2.zip' }
        }
        $null = InModuleScope IntuneScriptLab {
            Get-IslExportReport -ReportName 'DeviceInstallStatusByApp' -Filter "(ApplicationId eq 'app-a')" `
                -Select 'DeviceName', 'InstallState'
        }
        Should-Invoke Invoke-IslGraphRequest -ModuleName IntuneScriptLab -ParameterFilter {
            $Method -eq 'POST' -and $Body.filter -eq "(ApplicationId eq 'app-a')" -and
            @($Body.select).Count -eq 2
        } -Times 1 -Exactly
    }

    It 'fails when the job ends in failure' {
        Mock Invoke-IslGraphRequest -ModuleName IntuneScriptLab { @{ id = 'job-3'; status = 'failed' } }
        { InModuleScope IntuneScriptLab { Get-IslExportReport -ReportName 'AppInstallStatusAggregate' } } |
            Should-Throw -ExceptionMessage "*ended with status 'failed'*"
    }

    It 'fails when the job does not complete in time' {
        Mock Invoke-IslGraphRequest -ModuleName IntuneScriptLab { @{ id = 'job-4'; status = 'inProgress' } }
        { InModuleScope IntuneScriptLab { Get-IslExportReport -ReportName 'X' -TimeoutSeconds -1 } } |
            Should-Throw -ExceptionMessage '*did not complete within*'
    }
}
