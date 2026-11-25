#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    One Graph request with its retries. The waits themselves are tested through
    Invoke-IslGraphRequest and Get-IslGraphRetryDelay; this file holds what the function gives
    back. Invoke-MgGraphRequest is stood in for by a global stub so no Graph module is needed.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }
    if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) {
        # The parameters exist so the mocks' parameter filters can bind to them
        function global:Invoke-MgGraphRequest {
            param($Method, $Uri, $Body, $Headers, $ErrorAction)
            $null = $Method, $Uri, $Body, $Headers, $ErrorAction
        }
        $script:StubCreated = $true
    }
    Mock Start-Sleep -ModuleName IntuneScriptLab { }

    function script:Invoke-Once {
        param([hashtable]$Request)
        InModuleScope IntuneScriptLab -Parameters @{ Request = $Request } {
            Invoke-IslGraphRequestOnce -Request $Request
        }
    }
}

AfterAll {
    if ($script:StubCreated) { Remove-Item Function:\global:Invoke-MgGraphRequest -ErrorAction SilentlyContinue }
}

Describe 'Invoke-IslGraphRequestOnce' -Tag 'Unit', 'Private' {

    It 'passes the request through and returns the reply as it came' {
        Mock Invoke-MgGraphRequest -ModuleName IntuneScriptLab { @{ id = 'x'; method = $Method; uri = $Uri } }

        $reply = Invoke-Once @{ Method = 'GET'; Uri = '/beta/things/x'; ErrorAction = 'Stop' }

        $reply['id'] | Should-Be 'x'
        $reply['method'] | Should-Be 'GET'
        $reply['uri'] | Should-Be '/beta/things/x'
        Should-Invoke Invoke-MgGraphRequest -ModuleName IntuneScriptLab -Times 1 -Exactly
    }

    It 'ends with the error of a failure that is not sent again, as Graph raised it' {
        $failure = [System.InvalidOperationException]::new('Response status code does not indicate success: 404')
        Mock Invoke-MgGraphRequest -ModuleName IntuneScriptLab { throw $failure }

        $thrown = { Invoke-Once @{ Method = 'GET'; Uri = '/beta/things/missing'; ErrorAction = 'Stop' } } |
            Should-Throw -ExceptionMessage '*404*'
        $thrown.Exception.GetBaseException() | Should-BeSame $failure
        Should-Invoke Invoke-MgGraphRequest -ModuleName IntuneScriptLab -Times 1 -Exactly
    }

    It 'sends the request again when Graph asks for it, and returns the reply that follows' {
        $script:Calls = 0
        Mock Get-IslGraphRetryDelay -ModuleName IntuneScriptLab { 1 }
        Mock Invoke-MgGraphRequest -ModuleName IntuneScriptLab {
            $script:Calls++
            if ($script:Calls -lt 3) { throw 'Response status code does not indicate success: 503' }
            @{ id = 'late' }
        }

        $reply = Invoke-Once @{ Method = 'GET'; Uri = '/beta/things/late'; ErrorAction = 'Stop' }

        $reply['id'] | Should-Be 'late'
        Should-Invoke Invoke-MgGraphRequest -ModuleName IntuneScriptLab -Times 3 -Exactly
    }
}
