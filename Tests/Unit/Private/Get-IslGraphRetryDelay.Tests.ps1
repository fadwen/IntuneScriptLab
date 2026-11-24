#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    How long to wait before a failed Graph request is sent again, read from the failure the way
    Invoke-MgGraphRequest raises it.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }
    # Windows PowerShell 5.1 loads System.Net.Http on demand
    Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue

    function script:New-GraphFailureRecord {
        param([int]$StatusCode, [int]$RetryAfterSeconds)
        # .NET Framework's HttpStatusCode has no name for 429; the enum takes the number all the same
        $code = [System.Enum]::ToObject([System.Net.HttpStatusCode], $StatusCode)
        $response = [System.Net.Http.HttpResponseMessage]::new($code)
        if ($RetryAfterSeconds) {
            $delta = [timespan]::FromSeconds($RetryAfterSeconds)
            $response.Headers.RetryAfter = [System.Net.Http.Headers.RetryConditionHeaderValue]::new($delta)
        }
        $failure = [RetryDelayGraphException]::new("Response status code does not indicate success: $StatusCode")
        $failure.StatusCode = $code
        $failure.Response = $response
        [System.Management.Automation.ErrorRecord]::new($failure, 'GraphFailure', 'InvalidResult', $null)
    }

    function script:Get-Delay {
        param([System.Management.Automation.ErrorRecord]$Record, [int]$Attempt)
        $parameters = @{ Record = $Record; Attempt = $Attempt }
        InModuleScope IntuneScriptLab -Parameters $parameters {
            Get-IslGraphRetryDelay -ErrorRecord $Record -Attempt $Attempt
        }
    }
}

class RetryDelayGraphException : System.Exception {
    $StatusCode
    $Response
    RetryDelayGraphException([string]$message) : base($message) { }
}

Describe 'Get-IslGraphRetryDelay' -Tag 'Unit', 'Private' {

    It 'waits the Retry-After seconds of a throttled request' {
        Get-Delay -Record (New-GraphFailureRecord -StatusCode 429 -RetryAfterSeconds 7) -Attempt 1 | Should-Be 7
    }

    It 'doubles the wait with each attempt for <Status> without Retry-After' -ForEach @(
        @{ Status = 503 }
        @{ Status = 504 }
        @{ Status = 429 }
    ) {
        $record = New-GraphFailureRecord -StatusCode $Status
        @(1, 2, 3 | ForEach-Object { Get-Delay -Record $record -Attempt $_ }) | Should-BeCollection -Count 3
        Get-Delay -Record $record -Attempt 1 | Should-Be 2
        Get-Delay -Record $record -Attempt 2 | Should-Be 4
        Get-Delay -Record $record -Attempt 3 | Should-Be 8
    }

    It 'waits at most 60 seconds' {
        Get-Delay -Record (New-GraphFailureRecord -StatusCode 429 -RetryAfterSeconds 600) -Attempt 1 | Should-Be 60
    }

    It 'gives nothing for a failure that is not sent again: <Status>' -ForEach @(
        @{ Status = 400 }
        @{ Status = 403 }
        @{ Status = 404 }
        @{ Status = 500 }
    ) {
        @(Get-Delay -Record (New-GraphFailureRecord -StatusCode $Status) -Attempt 1) | Should-BeCollection @()
    }

    It 'gives nothing for a failure that carries no status at all' {
        $record = [System.Management.Automation.ErrorRecord]::new(
            [System.InvalidOperationException]::new('no connection'), 'NoStatus', 'ConnectionError', $null)

        @(Get-Delay -Record $record -Attempt 1) | Should-BeCollection @()
    }
}
