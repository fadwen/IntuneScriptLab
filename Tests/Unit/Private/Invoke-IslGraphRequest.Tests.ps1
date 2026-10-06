#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The Graph seam: the message when Microsoft.Graph.Authentication is absent, the pass-through of
    method, URI and body, and paging with -All. Invoke-MgGraphRequest is stood in for by a global
    stub so no Graph module is needed.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) {
        # The parameters exist so the mocks' parameter filters can bind to them
        function global:Invoke-MgGraphRequest {
            param($Method, $Uri, $Body, $Headers, $ErrorAction)
            $null = $Method, $Uri, $Body, $Headers, $ErrorAction
        }
        $script:StubCreated = $true
    }
    # What Invoke-MgGraphRequest throws, as far as the seam reads it: a StatusCode and a Response
    # whose headers may carry Retry-After. Windows PowerShell 5.1 loads System.Net.Http on demand
    Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
    function script:New-GraphFailure {
        param([int]$StatusCode, [int]$RetryAfterSeconds)
        # .NET Framework's HttpStatusCode has no name for 429; the enum takes the number all the same
        $code = [System.Enum]::ToObject([System.Net.HttpStatusCode], $StatusCode)
        $response = [System.Net.Http.HttpResponseMessage]::new($code)
        if ($RetryAfterSeconds) {
            $delta = [timespan]::FromSeconds($RetryAfterSeconds)
            $response.Headers.RetryAfter = [System.Net.Http.Headers.RetryConditionHeaderValue]::new($delta)
        }
        $failure = [FakeGraphException]::new("Response status code does not indicate success: $StatusCode")
        $failure.StatusCode = $code
        $failure.Response = $response
        $failure
    }
}

class FakeGraphException : System.Exception {
    $StatusCode
    $Response
    FakeGraphException([string]$message) : base($message) { }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
    if ($script:StubCreated) { Remove-Item Function:\global:Invoke-MgGraphRequest -ErrorAction SilentlyContinue }
}

Describe 'Invoke-IslGraphRequest' -Tag 'Unit', 'Private' {

    It 'explains what to install and connect when the Graph module is not loaded' {
        $graphCommand = { $Name -eq 'Invoke-MgGraphRequest' }
        Mock Get-Command -ModuleName IntuneScriptLab { $null } -ParameterFilter $graphCommand
        { InModuleScope IntuneScriptLab { Invoke-IslGraphRequest -Uri '/v1.0/me' } } |
            Should-Throw -ExceptionMessage '*Microsoft.Graph.Authentication*Connect-MgGraph*'
    }

    It 'passes the method, URI and body through and returns the reply as is' {
        Mock Invoke-MgGraphRequest -ModuleName IntuneScriptLab { @{ id = 'x'; echo = $Uri } }
        $reply = InModuleScope IntuneScriptLab {
            Invoke-IslGraphRequest -Method POST -Uri '/beta/things' -Body @{ name = 'n' }
        }
        $reply.echo | Should-Be '/beta/things'
        Should-Invoke Invoke-MgGraphRequest -ModuleName IntuneScriptLab -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Body.name -eq 'n'
        }
    }

    It 'follows @odata.nextLink with -All and returns every item' {
        Mock Invoke-MgGraphRequest -ModuleName IntuneScriptLab {
            if ($Uri -like '*skiptoken*') { @{ value = @(@{ id = 3 }) } }
            else { @{ value = @(@{ id = 1 }, @{ id = 2 }); '@odata.nextLink' = "$Uri&`$skiptoken=abc" } }
        }
        $items = @(InModuleScope IntuneScriptLab { Invoke-IslGraphRequest -Uri '/beta/things?$select=id' -All })
        $items.id | Should-BeCollection @(1, 2, 3)
        Should-Invoke Invoke-MgGraphRequest -ModuleName IntuneScriptLab -Times 2 -Exactly
    }

    It 'returns nothing for an empty collection with -All' {
        Mock Invoke-MgGraphRequest -ModuleName IntuneScriptLab { @{ value = @() } }
        @(InModuleScope IntuneScriptLab { Invoke-IslGraphRequest -Uri '/beta/things' -All }).Count | Should-Be 0
    }

    It 'passes request headers through' {
        Mock Invoke-MgGraphRequest -ModuleName IntuneScriptLab { '17' }
        $reply = InModuleScope IntuneScriptLab {
            Invoke-IslGraphRequest -Uri '/v1.0/groups/g/members/$count' -Headers @{ ConsistencyLevel = 'eventual' }
        }
        $reply | Should-Be '17'
        Should-Invoke Invoke-MgGraphRequest -ModuleName IntuneScriptLab -Times 1 -Exactly -ParameterFilter {
            $Headers.ConsistencyLevel -eq 'eventual'
        }
    }

    Context 'Retry' {
        BeforeEach {
            Mock Start-Sleep -ModuleName IntuneScriptLab { }
            $script:Failures = [System.Collections.Generic.List[object]]::new()
            # Throws the next queued failure, or returns the answer given
            function script:Invoke-NextFailure {
                param($Answer)
                if ($script:Failures.Count) {
                    $next = $script:Failures[0]
                    $script:Failures.RemoveAt(0)
                    throw $next
                }
                $Answer
            }
        }

        It 'sends a throttled request again after the Retry-After seconds, then returns the answer' {
            $script:Failures.Add((New-GraphFailure -StatusCode 429 -RetryAfterSeconds 7))
            $script:Failures.Add((New-GraphFailure -StatusCode 429 -RetryAfterSeconds 3))
            Mock Invoke-MgGraphRequest -ModuleName IntuneScriptLab { Invoke-NextFailure -Answer @{ id = 'x' } }
            $reply = InModuleScope IntuneScriptLab { Invoke-IslGraphRequest -Uri '/beta/things/x' }
            $reply.id | Should-Be 'x'
            Should-Invoke Invoke-MgGraphRequest -ModuleName IntuneScriptLab -Times 3 -Exactly
            $sleepSplat = @{ ModuleName = 'IntuneScriptLab'; Times = 1; Exactly = $true }
            Should-Invoke Start-Sleep @sleepSplat -ParameterFilter { $Seconds -eq 7 }
            Should-Invoke Start-Sleep @sleepSplat -ParameterFilter { $Seconds -eq 3 }
        }

        It 'backs off 2, 4 and 8 seconds for <Status> without Retry-After, then throws the fourth' -ForEach @(
            @{ Status = 503 }
            @{ Status = 504 }
        ) {
            1..4 | ForEach-Object { $script:Failures.Add((New-GraphFailure -StatusCode $Status)) }
            Mock Invoke-MgGraphRequest -ModuleName IntuneScriptLab { Invoke-NextFailure }
            { InModuleScope IntuneScriptLab { Invoke-IslGraphRequest -Uri '/beta/things' } } |
                Should-Throw -ExceptionMessage "*$Status*"
            Should-Invoke Invoke-MgGraphRequest -ModuleName IntuneScriptLab -Times 4 -Exactly
            foreach ($seconds in 2, 4, 8) {
                $expected = $seconds
                Should-Invoke Start-Sleep -ModuleName IntuneScriptLab -Times 1 -Exactly -ParameterFilter {
                    $Seconds -eq $expected
                }
            }
        }

        It 'throws any other failure at once' {
            $script:Failures.Add((New-GraphFailure -StatusCode 404))
            Mock Invoke-MgGraphRequest -ModuleName IntuneScriptLab { Invoke-NextFailure }
            { InModuleScope IntuneScriptLab { Invoke-IslGraphRequest -Uri '/beta/things/missing' } } |
                Should-Throw -ExceptionMessage '*404*'
            Should-Invoke Invoke-MgGraphRequest -ModuleName IntuneScriptLab -Times 1 -Exactly
            Should-Invoke Start-Sleep -ModuleName IntuneScriptLab -Times 0 -Exactly
        }

        It 'retries a page in the middle of -All and keeps every item' {
            $script:Failures.Add((New-GraphFailure -StatusCode 429 -RetryAfterSeconds 1))
            Mock Invoke-MgGraphRequest -ModuleName IntuneScriptLab {
                if ($Uri -like '*skiptoken*') { Invoke-NextFailure -Answer @{ value = @(@{ id = 3 }) } }
                else { @{ value = @(@{ id = 1 }, @{ id = 2 }); '@odata.nextLink' = "$Uri&`$skiptoken=abc" } }
            }
            $items = @(InModuleScope IntuneScriptLab {
                    Invoke-IslGraphRequest -Uri '/beta/things?$select=id' -All
                })
            $items.id | Should-BeCollection @(1, 2, 3)
            Should-Invoke Invoke-MgGraphRequest -ModuleName IntuneScriptLab -Times 3 -Exactly
        }
    }
}
