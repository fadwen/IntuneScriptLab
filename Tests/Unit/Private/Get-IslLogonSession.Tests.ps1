#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The session list the credential launch relies on to tell whether the account it runs as holds a
    session (the agent runs user-context scripts inside the signed-in user's session,
    REM-PROBE-USER64). Sessions come from the owners of explorer.exe and sihost.exe through CIM,
    mocked here; one test reads the real machine for shape.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

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
        <#
        .SYNOPSIS
            Builds a fake shell process with a name, a session id and a process id.

        .DESCRIPTION
            Returns an object with the three members Get-IslLogonSession reads from a process, for
            the mock of Get-CimInstance to return in place of the machine's processes.

        .PARAMETER Name
            The name of the process, such as explorer.exe.

        .PARAMETER SessionId
            The session the process runs in.

        .PARAMETER ProcessId
            The id of the process, which picks its owner in $script:Owners.

        .EXAMPLE
            New-Shell 'explorer.exe' 1 100

            Returns an explorer.exe in session 1 with the process id 100.

        .INPUTS
            None.

        .OUTPUTS
            IntuneScriptLab.Test.ShellProcess. Name, SessionId and ProcessId.
        #>
        [CmdletBinding()]
        [OutputType('IntuneScriptLab.Test.ShellProcess')]
        param(
            [string]$Name,

            [int]$SessionId,

            [int]$ProcessId
        )

        [pscustomobject]@{
            PSTypeName = 'IntuneScriptLab.Test.ShellProcess'
            Name = $Name
            SessionId = $SessionId
            ProcessId = $ProcessId
        }
    }
    function script:Get-Session {
        <#
        .SYNOPSIS
            Gets the logon sessions Get-IslLogonSession finds among fake shell processes.

        .DESCRIPTION
            Mocks Get-CimInstance to return the shells, and Invoke-CimMethod to answer GetOwner and
            GetOwnerSid from $script:Owners by process id, then lists the sessions inside the module.
            A process whose owner is not in $script:Owners gets no answer.

        .PARAMETER Shells
            The shell processes of the fake machine, as New-Shell returns them.

        .EXAMPLE
            Get-Session @((New-Shell 'sihost.exe' 2 200))

            Returns the session of the account that owns process 200.

        .INPUTS
            None.

        .OUTPUTS
            IntuneScriptLab.LogonSession. What Get-IslLogonSession returns.
        #>
        [CmdletBinding()]
        [OutputType('IntuneScriptLab.LogonSession')]
        param(
            [object[]]$Shells
        )

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
