#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The SID behind one account name, and the name Windows gives that SID.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }
}

Describe 'ConvertTo-IslAccount' -Tag 'Unit', 'Private' {

    It 'gives the name Windows uses and the SID of a well-known account' {
        $account = InModuleScope IntuneScriptLab { ConvertTo-IslAccount -Name 'NT AUTHORITY\SYSTEM' }

        $account | Should-HaveType 'IntuneScriptLab.Account'
        $account.Sid | Should-Be 'S-1-5-18'
        $account.Name | Should-Be 'NT AUTHORITY\SYSTEM'
    }

    It 'gives nothing for a name Windows cannot resolve' {
        $name = "NOSUCHDOMAIN\nobody-$([guid]::NewGuid().ToString('N').Substring(0, 8))"

        InModuleScope IntuneScriptLab -Parameters @{ Name = $name } { ConvertTo-IslAccount -Name $Name } |
            Should-BeCollection @()
    }
}
