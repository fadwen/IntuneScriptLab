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
            param($Method, $Uri, $Body, $ErrorAction)
            $null = $Method, $Uri, $Body, $ErrorAction
        }
        $script:StubCreated = $true
    }
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
}
