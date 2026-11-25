#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    One Graph request with its retries. The waits themselves are tested through
    Invoke-IslGraphRequest and Get-IslGraphRetryDelay; this file holds what the function gives
    back. Invoke-MgGraphRequest is stood in for by a global stub so no Graph module is needed.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }
    if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) {
        function global:Invoke-MgGraphRequest {
            <#
            .SYNOPSIS
                Stands in for Invoke-MgGraphRequest where Microsoft.Graph.Authentication is missing.

            .DESCRIPTION
                The command has to exist for Mock to replace it, and a CI runner does not have the
                Graph module. The parameters are the ones the seam passes, so that the mocks'
                parameter filters can bind to them; -ErrorAction is the common parameter. Every
                test mocks it, so the body does nothing.

            .PARAMETER Method
                The HTTP method.

            .PARAMETER Uri
                The request URI.

            .PARAMETER Body
                The request body.

            .PARAMETER Headers
                The request headers.

            .EXAMPLE
                Invoke-MgGraphRequest -Method GET -Uri '/v1.0/me'

                Returns nothing unless a test mocks it.

            .INPUTS
                None.

            .OUTPUTS
                None.
            #>
            [CmdletBinding()]
            [OutputType([void])]
            param(
                [string]$Method,

                [string]$Uri,

                [object]$Body,

                [object]$Headers
            )

            $null = $Method, $Uri, $Body, $Headers
        }
        $script:StubCreated = $true
    }
    Mock Start-Sleep -ModuleName IntuneScriptLab { }

    function script:Invoke-Once {
        <#
        .SYNOPSIS
            Runs one Graph request with the module's private Invoke-IslGraphRequestOnce.

        .DESCRIPTION
            Runs Invoke-IslGraphRequestOnce inside the module, where the private function and the
            mocks of Invoke-MgGraphRequest and Start-Sleep apply, and returns the reply as it came.

        .PARAMETER Request
            The parameters of Invoke-MgGraphRequest, such as Method, Uri and ErrorAction.

        .EXAMPLE
            Invoke-Once @{ Method = 'GET'; Uri = '/beta/things/x'; ErrorAction = 'Stop' }

            Sends the request to the mocked Invoke-MgGraphRequest and returns its reply.

        .INPUTS
            None.

        .OUTPUTS
            System.Object. The reply of the request.
        #>
        [CmdletBinding()]
        [OutputType([object])]
        param(
            [hashtable]$Request
        )

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
