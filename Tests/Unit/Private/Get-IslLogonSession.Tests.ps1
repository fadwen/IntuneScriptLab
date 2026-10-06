#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The session list the credential launch relies on to tell whether the account it runs as holds a
    session (the agent runs user-context scripts inside the signed-in user's session,
    REM-PROBE-USER64). Sessions come from the owners of explorer.exe and sihost.exe through CIM,
    mocked here; one test reads the real machine for shape.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force

    # The fake machine: shell processes by session, and what GetOwner / GetOwnerSid answer for each.
    # Module-scoped mocks see this file's $script: variables
    $script:EntraSid = 'S-1-12-1-1497552185-1263987200-3276725654-805488699'
    $script:LocalSid = 'S-1-5-21-1-2-3-1001'
    $script:Owners = @{
        100 = @{ Domain = 'KRBETYP-AIEPVQ5'; User = 'isl-user'; Sid = $script:LocalSid }
        101 = @{ Domain = 'KRBETYP-AIEPVQ5'; User = 'isl-user'; Sid = $script:LocalSid }
        200 = @{ Domain = 'AzureAD'; User = 'IslVerylongdisplayna'; Sid = $script:EntraSid }
        300 = $null   # an owner this session may not read
    }
    function script:New-Shell {
        param([string]$Name, [int]$SessionId, [int]$ProcessId)
        [pscustomobject]@{ Name = $Name; SessionId = $SessionId; ProcessId = $ProcessId }
    }
    function script:Get-Session {
        param([object[]]$Shells)
        $script:Shells = $Shells
        Mock Get-CimInstance -ModuleName IntuneScriptLab { $script:Shells }
        # The fake shells are plain objects, not CimInstances, so the parameter's type is lifted
        Mock Invoke-CimMethod -ModuleName IntuneScriptLab -RemoveParameterType InputObject {
            $owner = $script:Owners[[int]$InputObject.ProcessId]
            if (-not $owner) { return }
            if ($MethodName -eq 'GetOwnerSid') { [pscustomobject]@{ Sid = $owner.Sid } }
            else { [pscustomobject]@{ Domain = $owner.Domain; User = $owner.User } }
        }
        InModuleScope IntuneScriptLab { @(Get-IslLogonSession) }
    }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Get-IslLogonSession' -Tag 'Unit', 'Private' {

    It 'lists one session per desktop user, from the owner of its shell processes' {
        $sessions = Get-Session @(
            (New-Shell 'sihost.exe' 1 101), (New-Shell 'explorer.exe' 1 100), (New-Shell 'explorer.exe' 2 200)
        )
        $sessions.Count | Should-Be 2
        $sessions[0].PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.LogonSession'
        $sessions[0].UserName | Should-Be 'isl-user'
        $sessions[0].Domain | Should-Be 'KRBETYP-AIEPVQ5'
        $sessions[0].Sid | Should-Be $script:LocalSid
        $sessions[0].Id | Should-Be 1
        # The Entra account by the name Windows gives it, not its sign-in name (VM 125)
        $sessions[1].UserName | Should-Be 'IslVerylongdisplayna'
        $sessions[1].Domain | Should-Be 'AzureAD'
        $sessions[1].Sid | Should-Be $script:EntraSid
        $sessions[1].Id | Should-Be 2
    }

    It 'lists a session whose desktop is still starting, from sihost.exe alone' {
        $sessions = @(Get-Session @((New-Shell 'sihost.exe' 2 200)))
        $sessions.Count | Should-Be 1
        $sessions[0].Sid | Should-Be $script:EntraSid
    }

    It 'leaves out a process whose owner it may not read, and returns nothing with no desktop at all' {
        $sessions = @(Get-Session @((New-Shell 'explorer.exe' 3 300), (New-Shell 'explorer.exe' 1 100)))
        $sessions.Count | Should-Be 1
        $sessions[0].Id | Should-Be 1
        @(Get-Session @()).Count | Should-Be 0
    }

    It 'reads the real machine without error and gives every session a SID and an id' {
        # A CI runner has no desktop session; this machine has at least the one running the tests
        $real = @(InModuleScope IntuneScriptLab { Get-IslLogonSession })
        foreach ($session in $real) {
            $session.Sid | Should-MatchString '^S-1-'
            $session.UserName | Should-NotBeWhiteSpaceString
            $session.Id | Should-BeGreaterThanOrEqual 0
        }
    }
}
