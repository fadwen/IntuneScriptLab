#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    What Windows calls the account a credential names. The lookups themselves run against this
    machine's own accounts; the Entra case, which needs a joined device with the user signed in, is
    played back from what the lab device answered on 2026-10-05.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    $script:Me = [System.Security.Principal.WindowsIdentity]::GetCurrent()

    function Resolve-Account {
        param([string]$Name)
        InModuleScope IntuneScriptLab -Parameters @{ Name = $Name } { Resolve-IslAccount -Name $Name }
    }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Resolve-IslAccount' -Tag 'Unit', 'Private' {

    Context 'Against this machine' {
        It 'returns the Windows name and the SID of the account running the tests' {
            $account = Resolve-Account $script:Me.Name
            $account.PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.Account'
            $account.Name | Should-Be $script:Me.Name
            $account.Sid | Should-Be $script:Me.User.Value
        }

        It 'turns a well-known name into the name Windows uses for it' {
            $account = Resolve-Account 'SYSTEM'
            $account.Sid | Should-Be 'S-1-5-18'
            $account.Name | Should-BeLikeString '*\SYSTEM'
        }

        It 'returns nothing for a name Windows cannot resolve' {
            # Qualified with this machine's name, so the lookup stays local and quick
            @(Resolve-Account "$env:COMPUTERNAME\no-such-account-for-isl").Count | Should-Be 0
        }
    }

    Context 'A Microsoft Entra account (VM 125)' {
        BeforeEach {
            # What the joined device answered: the sign-in name resolves only behind AzureAD\, and
            # the SID's own name is the display name without spaces, cut at 20 characters
            Mock ConvertTo-IslAccount -ModuleName IntuneScriptLab {
                if ($Name -in 'AzureAD\isl-verylongusername-test01@4nlnm3.onmicrosoft.com',
                    'AzureAD\IslVerylongdisplayna') {
                    [pscustomobject]@{
                        Name = 'AzureAD\IslVerylongdisplayna'
                        Sid  = 'S-1-12-1-1497552185-1263987200-3276725654-805488699'
                    }
                }
            }
        }

        It 'resolves the sign-in name by trying it behind AzureAD\ when it does not resolve as given' {
            $account = Resolve-Account 'isl-verylongusername-test01@4nlnm3.onmicrosoft.com'
            $account.Name | Should-Be 'AzureAD\IslVerylongdisplayna'
            $account.Sid | Should-Be 'S-1-12-1-1497552185-1263987200-3276725654-805488699'
            Should-Invoke ConvertTo-IslAccount -ModuleName IntuneScriptLab -Exactly -Times 2
        }

        It 'resolves the Windows name as given, in one lookup' {
            (Resolve-Account 'AzureAD\IslVerylongdisplayna').Name | Should-Be 'AzureAD\IslVerylongdisplayna'
            Should-Invoke ConvertTo-IslAccount -ModuleName IntuneScriptLab -Exactly -Times 1
        }

        It 'does not guess a domain for a name that already has one, or for a bare name' {
            @(Resolve-Account 'CONTOSO\isl-verylongusername-test01').Count | Should-Be 0
            @(Resolve-Account 'isl-verylongusername-test01').Count | Should-Be 0
            Should-Invoke ConvertTo-IslAccount -ModuleName IntuneScriptLab -Exactly -Times 2
        }
    }
}
