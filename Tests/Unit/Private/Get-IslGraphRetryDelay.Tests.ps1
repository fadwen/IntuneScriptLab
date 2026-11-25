#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    How long to wait before a failed Graph request is sent again, read from the failure the way
    Invoke-MgGraphRequest raises it.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }
    # Windows PowerShell 5.1 loads System.Net.Http on demand
    Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue

    function script:New-GraphFailureRecord {
        <#
        .SYNOPSIS
            Creates an error record shaped like a failed Invoke-MgGraphRequest call.

        .DESCRIPTION
            Builds an exception with the status code and an HTTP response, with a Retry-After
            header when seconds are given, and wraps it in an error record, so that the delay is
            read from the same members a real Graph failure carries.

        .PARAMETER StatusCode
            The HTTP status code of the failure, such as 429 or 503.

        .PARAMETER RetryAfterSeconds
            The Retry-After header in seconds. Zero, the default, leaves the header out.

        .EXAMPLE
            New-GraphFailureRecord -StatusCode 429 -RetryAfterSeconds 7

            Creates the record of a throttled request that asks for a wait of seven seconds.

        .INPUTS
            None.

        .OUTPUTS
            System.Management.Automation.ErrorRecord. The record of the failure.
        #>
        [CmdletBinding()]
        [OutputType([System.Management.Automation.ErrorRecord])]
        param(
            [int]$StatusCode,

            [int]$RetryAfterSeconds
        )

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
        <#
        .SYNOPSIS
            Gets the retry delay the module's private function gives for a failure.

        .DESCRIPTION
            Calls Get-IslGraphRetryDelay inside the module, where the private function is
            visible, with the error record and the number of the attempt that failed.

        .PARAMETER Record
            The error record of the failed request.

        .PARAMETER Attempt
            The number of the attempt that failed, starting at 1.

        .EXAMPLE
            Get-Delay -Record (New-GraphFailureRecord -StatusCode 503) -Attempt 2

            Returns the seconds to wait after the second attempt failed with status 503.

        .INPUTS
            None.

        .OUTPUTS
            System.Int32. The seconds to wait, or nothing when the request is not retried.
        #>
        [CmdletBinding()]
        [OutputType([int])]
        param(
            [System.Management.Automation.ErrorRecord]$Record,

            [int]$Attempt
        )

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

    It 'doubles the wait for a <Status> whose response has no RetryAfter member' -ForEach @(
        @{ Status = 503 }
        @{ Status = 429 }
    ) {
        # The shape of a WebException's HttpWebResponse: a status code and a header collection
        # that holds Retry-After as text, with no RetryAfter member
        $headers = [System.Net.WebHeaderCollection]::new()
        $headers.Add('Retry-After', '7')
        $failure = [RetryDelayGraphException]::new("Response status code does not indicate success: $Status")
        $failure.Response = [pscustomobject]@{ StatusCode = $Status; Headers = $headers }
        $record = [System.Management.Automation.ErrorRecord]::new($failure, 'WebFailure', 'InvalidResult', $null)

        Get-Delay -Record $record -Attempt 2 | Should-Be 4
    }

    It 'gives nothing for a failure that carries no status at all' {
        $record = [System.Management.Automation.ErrorRecord]::new(
            [System.InvalidOperationException]::new('no connection'), 'NoStatus', 'ConnectionError', $null)

        @(Get-Delay -Record $record -Attempt 1) | Should-BeCollection @()
    }
}
