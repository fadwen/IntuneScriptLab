#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The "query user" parser the credential launch relies on to tell whether the account it runs as
    holds a session (the agent runs user-context scripts inside the signed-in user's session,
    REM-PROBE-USER64). The tool's output is mocked; one test reads the real tool for shape.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force

    function script:Get-SessionFromText {
        param([string[]]$Lines)
        InModuleScope IntuneScriptLab -Parameters @{ Lines = $Lines } {
            Mock Get-IslQueryUserOutput { $Lines }
            @(Get-IslLogonSession)
        }
    }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Get-IslLogonSession' -Tag 'Unit', 'Private' {

    It 'parses an active console session and a disconnected one without a session name' {
        $sessions = Get-SessionFromText -Lines @(
            ' USERNAME              SESSIONNAME        ID  STATE   IDLE TIME  LOGON TIME'
            '>jeffstuhr             console             2  Active      none   9/23/2026 8:50 AM'
            ' isl-user                                  3  Disc         1:23  9/28/2026 1:02 AM'
        )
        $sessions.Count | Should-Be 2
        $sessions[0].PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.LogonSession'
        $sessions[0].UserName | Should-Be 'jeffstuhr'
        $sessions[0].SessionName | Should-Be 'console'
        $sessions[0].Id | Should-Be 2
        $sessions[0].State | Should-Be 'Active'
        $sessions[1].UserName | Should-Be 'isl-user'
        $sessions[1].SessionName | Should-Be ''
        $sessions[1].Id | Should-Be 3
        $sessions[1].State | Should-Be 'Disc'
    }

    It 'reads a 20-character name, the longest Windows gives an account, as printed on VM 125' {
        # An Entra user named "Isl Verylongdisplayname Testaccount" who signs in as
        # isl-verylongusername-test01@...: Windows calls it AzureAD\IslVerylongdisplayna, the display
        # name without spaces cut at 20 characters, and the column still ends in two spaces
        $sessions = @(Get-SessionFromText -Lines @(
                ' USERNAME              SESSIONNAME        ID  STATE   IDLE TIME  LOGON TIME'
                ' islverylongdisplayna  console             2  Active      none   10/5/2026 11:05 AM'
            ))
        $sessions.Count | Should-Be 1
        $sessions[0].UserName | Should-Be 'islverylongdisplayna'
        $sessions[0].SessionName | Should-Be 'console'
        $sessions[0].Id | Should-Be 2
    }

    It 'returns nothing when nobody is logged on, the tool is missing, or only the header prints' {
        @(Get-SessionFromText -Lines @()).Count | Should-Be 0
        @(Get-SessionFromText -Lines @(' USERNAME  SESSIONNAME  ID  STATE  IDLE TIME  LOGON TIME')).Count |
            Should-Be 0
    }

    It 'skips lines it cannot read rather than failing' {
        $sessions = @(Get-SessionFromText -Lines @(
                ' USERNAME              SESSIONNAME        ID  STATE   IDLE TIME  LOGON TIME'
                'garbage line'
                ' isl-user              rdp-tcp#1           4  Active      none   9/28/2026 1:02 AM'
            ))
        $sessions.Count | Should-Be 1
        $sessions[0].SessionName | Should-Be 'rdp-tcp#1'
    }

    It 'reads the real tool without error and names a user for every session it finds' {
        $real = @(InModuleScope IntuneScriptLab { Get-IslLogonSession })
        foreach ($session in $real) {
            $session.UserName | Should-NotBeWhiteSpaceString
            $session.Id | Should-BeGreaterThanOrEqual 0
        }
    }
}
