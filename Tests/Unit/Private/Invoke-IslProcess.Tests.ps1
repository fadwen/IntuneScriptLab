#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The process launcher. User runs a real cmd.exe (milliseconds) to check the capture,
    the closed stdin and the kill on timeout. The SYSTEM branch is exercised with the scheduled
    task cmdlets mocked: the fake task writes the output files the real one would, so the wrapper
    command, the polling and the cleanup are covered without elevation.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
    $script:Cmd = Join-Path $env:WINDIR 'System32\cmd.exe'

    function Invoke-Process {
        <#
        .SYNOPSIS
            Runs a process with the module's private Invoke-IslProcess.

        .DESCRIPTION
            Calls Invoke-IslProcess inside the module, where the private function is visible,
            with the given parameters splatted onto it.

        .PARAMETER Parameters
            The parameters of Invoke-IslProcess, such as FilePath, Arguments and Context.

        .EXAMPLE
            Invoke-Process $script:LaunchSplat

            Starts the process that the splat describes and returns its result.

        .INPUTS
            None.

        .OUTPUTS
            IntuneScriptLab.ProcessResult. The result of the process.
        #>
        [CmdletBinding()]
        [OutputType('IntuneScriptLab.ProcessResult')]
        param(
            [hashtable]$Parameters
        )

        InModuleScope IntuneScriptLab -Parameters @{ Parameters = $Parameters } { Invoke-IslProcess @Parameters }
    }
}

Describe 'Invoke-IslProcess' -Tag 'Unit', 'Private' {

    # Child processes for real: the module's own launch, a timeout, a process tree
    Context 'Current user' -Tag 'Integration' {
        It 'captures the exit code, stdout and stderr of a child process' {
            $result = Invoke-Process @{
                FilePath = $script:Cmd; Arguments = '/C echo out& echo err 1>&2& exit 3'
                WorkingDirectory = $TestDrive; WorkFolder = $TestDrive
            }
            $result.ExitCode | Should-Be 3
            $result.StdOut.Trim() | Should-Be 'out'
            $result.StdErr.Trim() | Should-Be 'err'
            $result.TimedOut | Should-BeFalse
            $result.Context | Should-Be 'User'
            ($result.Duration -is [timespan]) | Should-BeTrue
            $result.PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.ProcessResult'
        }

        It 'says which executable could not be started' {
            $missing = Join-Path $TestDrive 'no-such-host.exe'
            $failure = { Invoke-Process @{
                    FilePath = $missing; WorkingDirectory = $TestDrive; WorkFolder = $TestDrive
                } } | Should-Throw
            $failure.Exception.Message | Should-BeLikeString "Could not start '$missing': *"
            $failure.FullyQualifiedErrorId | Should-BeLikeString 'ProcessStartFailed,*'
        }

        It 'ends with the error of a cleanup that could not be run after a timeout' {
            # A TimedOut result would say that the tree is gone. The mock notes the process it was
            # asked to end, and the test ends it afterwards
            $script:LeftRunning = $null
            Mock Stop-IslProcessTree -ModuleName IntuneScriptLab {
                $script:LeftRunning = $ProcessId
                throw 'taskkill.exe could not be started'
            }
            try {
                $failure = { Invoke-Process @{
                        FilePath = $script:Cmd; Arguments = '/D /C ping.exe -n 30 127.0.0.1 > nul'
                        WorkingDirectory = [System.Environment]::SystemDirectory; WorkFolder = $TestDrive
                        TimeoutSeconds = 1
                    } } | Should-Throw
                $failure.Exception.Message | Should-BeLikeString '*taskkill.exe could not be started*'
                $script:LeftRunning | Should-NotBeNull
            } finally {
                if ($script:LeftRunning) {
                    $null = & $script:Cmd /D /C "taskkill.exe /PID $($script:LeftRunning) /T /F > nul 2>&1"
                }
            }
        }

        It 'runs in the working directory it is given' {
            $result = Invoke-Process @{
                FilePath = $script:Cmd; Arguments = '/C cd'; WorkingDirectory = $TestDrive; WorkFolder = $TestDrive
            }
            $result.StdOut.Trim() | Should-Be $TestDrive
        }

        It 'lets cmd.exe find a batch file in the working folder whatever the caller''s own shell setting' {
            # NoDefaultCurrentDirectoryInExePath in the caller's environment stops cmd.exe looking in
            # the working folder; the agent's cmd.exe has no such setting, so the child must not either
            Set-Content -Path (Join-Path $TestDrive 'install.cmd') -Value '@echo ran' -Encoding ascii
            $saved = $env:NoDefaultCurrentDirectoryInExePath
            $env:NoDefaultCurrentDirectoryInExePath = '1'
            try {
                $result = Invoke-Process @{
                    FilePath = $script:Cmd; Arguments = '/C "install.cmd"'
                    WorkingDirectory = $TestDrive; WorkFolder = $TestDrive
                }
            } finally {
                $env:NoDefaultCurrentDirectoryInExePath = $saved
            }
            $result.ExitCode | Should-Be 0
            $result.StdOut.Trim() | Should-Be 'ran'
            $result.StdErr.Trim() | Should-Be ''
        }

        It 'closes stdin so a read returns instead of waiting' {
            $result = Invoke-Process @{
                FilePath = $script:Cmd; Arguments = '/C set /p answer=name? & echo [%answer%]'
                WorkingDirectory = $TestDrive; WorkFolder = $TestDrive; TimeoutSeconds = 20
            }
            $result.TimedOut | Should-BeFalse
        }

        It 'hands the child the session module path without the folders PowerShell 7 adds for itself' {
            # Under Windows PowerShell there is nothing to remove and the path arrives whole
            $added = Join-Path $TestDrive 'SessionModules'
            $saved = $env:PSModulePath
            $env:PSModulePath = "$saved;$added"
            try {
                $result = Invoke-Process @{
                    FilePath = $script:Cmd; Arguments = '/C echo %PSModulePath%'
                    WorkingDirectory = $TestDrive; WorkFolder = $TestDrive
                }
            } finally { $env:PSModulePath = $saved }
            $entries = @($result.StdOut.Trim() -split ';')
            @($entries | Where-Object { $_ -eq $added }).Count | Should-Be 1
            if ($PSVersionTable.PSEdition -eq 'Core') {
                @($entries | Where-Object { $_ -eq (Join-Path $PSHOME 'Modules') }).Count | Should-Be 0
            } else { $result.StdOut.Trim() | Should-Be "$saved;$added" }
        }

        It 'kills the process tree at the timeout and reports no exit code' {
            $result = Invoke-Process @{
                FilePath = $script:Cmd; Arguments = '/C ping -n 30 127.0.0.1 > nul'
                WorkingDirectory = $TestDrive; WorkFolder = $TestDrive; TimeoutSeconds = 1
            }
            $result.TimedOut | Should-BeTrue
            $result.ExitCode | Should-BeNull
            $result.Duration.TotalSeconds | Should-BeLessThan 15
        }
    }

    Context 'System' {
        BeforeEach {
            # A clock of the test's own (TST-31): the task loop polls every 250 ms and gives up on a
            # task that never starts after 5 seconds, which on the real clock made each test here
            # wait that long. Start-Sleep moves the clock on instead of waiting
            $script:Clock = [datetime]'2026-01-01T00:00:00'
            Mock Get-Date -ModuleName IntuneScriptLab { $script:Clock }
            Mock Start-Sleep -ModuleName IntuneScriptLab {
                $milliseconds = [int]$PesterBoundParameters['Milliseconds']
                $seconds = [int]$PesterBoundParameters['Seconds']
                $script:Clock = $script:Clock.AddMilliseconds($milliseconds).AddSeconds($seconds)
            }
            # The work folder's leaf is the run id the task name carries, so the fake task can find
            # the folder from the name alone, as the mocks see only their own parameters
            $script:WorkFolder = Join-Path ([IO.Path]::GetTempPath()) "IslTest-$([guid]::NewGuid().ToString('N'))"
            $null = New-Item -ItemType Directory -Path $script:WorkFolder -Force
            Mock Register-ScheduledTask -ModuleName IntuneScriptLab { }
            Mock Unregister-ScheduledTask -ModuleName IntuneScriptLab { }
            Mock Stop-ScheduledTask -ModuleName IntuneScriptLab { }
            Mock Get-ScheduledTask -ModuleName IntuneScriptLab { [pscustomobject]@{ State = 'Ready' } }
            Mock Get-CimInstance -ModuleName IntuneScriptLab { }
            Mock Start-ScheduledTask -ModuleName IntuneScriptLab {
                $folder = Join-Path ([IO.Path]::GetTempPath()) $TaskName.Substring('IntuneScriptLab-'.Length)
                [IO.File]::WriteAllText((Join-Path $folder 'stdout.txt'), "sys-out`r`n")
                [IO.File]::WriteAllText((Join-Path $folder 'stderr.txt'), '')
                [IO.File]::WriteAllText((Join-Path $folder 'exitcode.txt'), "5`r`n")
            }
        }

        AfterEach {
            Remove-Item $script:WorkFolder -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'registers a one-shot SYSTEM task wrapping the command in cmd.exe with redirected output' {
            $result = Invoke-Process @{
                FilePath = 'C:\host\powershell.exe'; Arguments = '-File "x.ps1"'
                WorkingDirectory = 'C:\Windows\System32'
                WorkFolder = $script:WorkFolder; Context = 'System'; TimeoutSeconds = 30
            }
            $result.ExitCode | Should-Be 5
            $result.StdOut | Should-Be "sys-out`r`n"
            $result.Context | Should-Be 'System'
            $runId = Split-Path $script:WorkFolder -Leaf
            Should-Invoke Register-ScheduledTask -ModuleName IntuneScriptLab -Exactly -Times 1 -ParameterFilter {
                $TaskName -eq "IntuneScriptLab-$runId" -and
                $Principal.UserId -eq 'SYSTEM' -and
                $Action.Execute -like '*\System32\cmd.exe' -and
                $Action.Arguments -like '/V:ON /C ""C:\host\powershell.exe" -File "x.ps1" 1>"*stdout.txt" *' -and
                $Action.Arguments -like '*echo !ERRORLEVEL! >"*exitcode.txt""'
            }
            Should-Invoke Unregister-ScheduledTask -ModuleName IntuneScriptLab -Exactly -Times 1
        }

        It 'removes the task although the caller''s WhatIf preference is on' {
            # Of the task cmdlets only Unregister-ScheduledTask has -WhatIf and -Confirm. Under a
            # WhatIf preference the task was registered and started, and then left on the computer
            $parameters = @{
                FilePath = 'C:\host\powershell.exe'; Arguments = '-File "x.ps1"'
                WorkingDirectory = 'C:\Windows\System32'
                WorkFolder = $script:WorkFolder; Context = 'System'; TimeoutSeconds = 30
            }
            $result = InModuleScope IntuneScriptLab -Parameters @{ Parameters = $parameters } {
                $WhatIfPreference = $true
                Invoke-IslProcess @Parameters
            }

            $result.ExitCode | Should-Be 5
            Should-Invoke Unregister-ScheduledTask -ModuleName IntuneScriptLab -Exactly -Times 1 -ParameterFilter {
                $PesterBoundParameters.ContainsKey('WhatIf') -and -not $WhatIf -and
                $PesterBoundParameters.ContainsKey('Confirm') -and -not $Confirm
            }
        }

        It 'uses the 32-bit cmd.exe when asked, so bare powershell.exe resolves to SysWOW64' {
            $null = Invoke-Process @{
                FilePath = 'powershell.exe'; WorkingDirectory = 'C:\'; WorkFolder = $script:WorkFolder
                Context = 'System'; LauncherBitness = 'x86'
            }
            Should-Invoke Register-ScheduledTask -ModuleName IntuneScriptLab -ParameterFilter {
                $Action.Execute -like '*\SysWOW64\cmd.exe'
            }
        }

        It 'turns a refused registration into an elevation message' {
            Mock Register-ScheduledTask -ModuleName IntuneScriptLab { throw 'Access is denied.' }
            $failure = { Invoke-Process @{
                    FilePath = 'x.exe'; WorkingDirectory = 'C:\'
                    WorkFolder = $script:WorkFolder; Context = 'System'
                } } | Should-Throw
            $failure.Exception.Message | Should-BeLikeString '*run elevated*Access is denied*'
            $failure.FullyQualifiedErrorId | Should-BeLikeString 'ScheduledTaskNotRegistered,*'
        }

        It 'reports TimedOut, stops the task and removes it when no exit file appears' {
            Mock Start-ScheduledTask -ModuleName IntuneScriptLab { }
            $result = Invoke-Process @{
                FilePath = 'x.exe'; WorkingDirectory = 'C:\'; WorkFolder = $script:WorkFolder; Context = 'System'
                TimeoutSeconds = 1
            }
            $result.TimedOut | Should-BeTrue
            $result.ExitCode | Should-BeNull
            Should-Invoke Stop-ScheduledTask -ModuleName IntuneScriptLab -Exactly -Times 1
            Should-Invoke Unregister-ScheduledTask -ModuleName IntuneScriptLab -Exactly -Times 1
        }
    }

    Context 'Another account' {
        BeforeEach {
            # A clock of the test's own (TST-31): the task loop polls every 250 ms and gives up on a
            # task that never starts after 5 seconds, which on the real clock made each test here
            # wait that long. Start-Sleep moves the clock on instead of waiting
            $script:Clock = [datetime]'2026-01-01T00:00:00'
            Mock Get-Date -ModuleName IntuneScriptLab { $script:Clock }
            Mock Start-Sleep -ModuleName IntuneScriptLab {
                $milliseconds = [int]$PesterBoundParameters['Milliseconds']
                $seconds = [int]$PesterBoundParameters['Seconds']
                $script:Clock = $script:Clock.AddMilliseconds($milliseconds).AddSeconds($seconds)
            }
            $script:WorkFolder = Join-Path ([IO.Path]::GetTempPath()) "IslTest-$([guid]::NewGuid().ToString('N'))"
            $null = New-Item -ItemType Directory -Path $script:WorkFolder -Force
            Mock Register-ScheduledTask -ModuleName IntuneScriptLab { }
            Mock Unregister-ScheduledTask -ModuleName IntuneScriptLab { }
            Mock Stop-ScheduledTask -ModuleName IntuneScriptLab { }
            Mock Get-ScheduledTask -ModuleName IntuneScriptLab { [pscustomobject]@{ State = 'Ready' } }
            # The accounts in these tests do not exist here: Windows resolves none of them
            Mock Resolve-IslAccount -ModuleName IntuneScriptLab { }
            Mock Start-ScheduledTask -ModuleName IntuneScriptLab {
                $folder = Join-Path ([IO.Path]::GetTempPath()) $TaskName.Substring('IntuneScriptLab-'.Length)
                [IO.File]::WriteAllText((Join-Path $folder 'stdout.txt'), "user-out`r`n")
                [IO.File]::WriteAllText((Join-Path $folder 'stderr.txt'), '')
                [IO.File]::WriteAllText((Join-Path $folder 'exitcode.txt'), "0`r`n")
            }
            $secure = [securestring]::new()
            foreach ($char in 'pw'.ToCharArray()) { $secure.AppendChar($char) }
            $script:Credential = [pscredential]::new('LAB\isl-user', $secure)
            $script:LaunchSplat = @{
                FilePath = 'C:\host\powershell.exe'; Arguments = '-File "x.ps1"'
                WorkingDirectory = 'C:\Windows\System32'; WorkFolder = $script:WorkFolder
                Credential = $script:Credential; TimeoutSeconds = 30
            }
        }

        AfterEach {
            Remove-Item $script:WorkFolder -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'registers an interactive task for the account when it holds a session (REM-PROBE-USER64)' {
            Mock Get-IslLogonSession -ModuleName IntuneScriptLab {
                [pscustomobject]@{ UserName = 'isl-user'; Domain = 'LAB'; Sid = 'S-1-5-21-1-2-3-1001'; Id = 2 }
            }
            $result = Invoke-Process $script:LaunchSplat
            $result.ExitCode | Should-Be 0
            $result.StdOut | Should-Be "user-out`r`n"
            $result.Context | Should-Be 'User'
            $result.UserName | Should-Be 'LAB\isl-user'
            $result.LogonType | Should-Be 'Interactive'
            Should-Invoke Register-ScheduledTask -ModuleName IntuneScriptLab -Exactly -Times 1 -ParameterFilter {
                $Principal.UserId -eq 'LAB\isl-user' -and "$($Principal.LogonType)" -eq 'Interactive' -and
                "$($Principal.RunLevel)" -eq 'Limited' -and $null -eq $Password
            }
            Should-Invoke Unregister-ScheduledTask -ModuleName IntuneScriptLab -Exactly -Times 1
        }

        It 'registers a stored-password task, run whether logged on or not, when the account has no session' {
            Mock Get-IslLogonSession -ModuleName IntuneScriptLab { @() }
            $result = Invoke-Process $script:LaunchSplat
            $result.LogonType | Should-Be 'Password'
            Should-Invoke Register-ScheduledTask -ModuleName IntuneScriptLab -Exactly -Times 1 -ParameterFilter {
                $User -eq 'LAB\isl-user' -and $Password -eq 'pw' -and "$RunLevel" -eq 'Limited' -and
                $null -eq $Principal
            }
        }

        It 'lets -LogonType force the stored-password task even when the account has a session' {
            Mock Get-IslLogonSession -ModuleName IntuneScriptLab {
                [pscustomobject]@{ UserName = 'isl-user'; Domain = 'LAB'; Sid = 'S-1-5-21-1-2-3-1001'; Id = 2 }
            }
            $result = Invoke-Process ($script:LaunchSplat + @{ LogonType = 'Password' })
            $result.LogonType | Should-Be 'Password'
            Should-Invoke Register-ScheduledTask -ModuleName IntuneScriptLab -Exactly -Times 1 -ParameterFilter {
                $User -eq 'LAB\isl-user' -and $Password -eq 'pw'
            }
        }

        It 'matches the session by account name whatever the credential prefix' {
            Mock Get-IslLogonSession -ModuleName IntuneScriptLab {
                [pscustomobject]@{ UserName = 'isl-user'; Domain = 'LAB'; Sid = 'S-1-5-21-1-2-3-1001'; Id = 2 }
            }
            $launchSplat = $script:LaunchSplat.Clone()
            $launchSplat.Credential = [pscredential]::new('isl-user@lab.local', $script:Credential.Password)
            $result = Invoke-Process $launchSplat
            $result.LogonType | Should-Be 'Interactive'
            $result.UserName | Should-Be 'isl-user@lab.local'
        }

        It 'finds an Entra account''s session by the name Windows gives it, not by its sign-in name (VM 125)' {
            # Signed in as isl-verylongusername-test01@..., the session owned by the SID that name
            # resolves to; the scheduler takes the Windows name and refuses the sign-in name
            Mock Resolve-IslAccount -ModuleName IntuneScriptLab {
                [pscustomobject]@{
                    Name = 'AzureAD\IslVerylongdisplayna'
                    Sid = 'S-1-12-1-1497552185-1263987200-3276725654-805488699'
                }
            }
            Mock Get-IslLogonSession -ModuleName IntuneScriptLab {
                [pscustomobject]@{
                    UserName = 'IslVerylongdisplayna'; Domain = 'AzureAD'
                    Sid = 'S-1-12-1-1497552185-1263987200-3276725654-805488699'; Id = 2
                }
            }
            $launchSplat = $script:LaunchSplat.Clone()
            $signInName = 'isl-verylongusername-test01@4nlnm3.onmicrosoft.com'
            $launchSplat.Credential = [pscredential]::new($signInName, $script:Credential.Password)
            $result = Invoke-Process $launchSplat
            $result.LogonType | Should-Be 'Interactive'
            $result.UserName | Should-Be $signInName
            Should-Invoke Resolve-IslAccount -ModuleName IntuneScriptLab -Exactly -Times 1 -ParameterFilter {
                $Name -eq 'isl-verylongusername-test01@4nlnm3.onmicrosoft.com'
            }
            Should-Invoke Register-ScheduledTask -ModuleName IntuneScriptLab -Exactly -Times 1 -ParameterFilter {
                $Principal.UserId -eq 'AzureAD\IslVerylongdisplayna' -and
                "$($Principal.LogonType)" -eq 'Interactive' -and $null -eq $Password
            }
        }

        It 'registers the stored-password task for an Entra account by its Windows name (VM 125)' {
            # The scheduler refuses the sign-in name with "No mapping between account names and
            # security IDs"; AzureAD\<Windows name> registers
            Mock Resolve-IslAccount -ModuleName IntuneScriptLab {
                [pscustomobject]@{
                    Name = 'AzureAD\IslVerylongdisplayna'
                    Sid = 'S-1-12-1-1497552185-1263987200-3276725654-805488699'
                }
            }
            Mock Get-IslLogonSession -ModuleName IntuneScriptLab { @() }
            $launchSplat = $script:LaunchSplat.Clone()
            $signInName = 'isl-verylongusername-test01@4nlnm3.onmicrosoft.com'
            $launchSplat.Credential = [pscredential]::new($signInName, $script:Credential.Password)
            $result = Invoke-Process $launchSplat
            $result.LogonType | Should-Be 'Password'
            $result.UserName | Should-Be $signInName
            Should-Invoke Register-ScheduledTask -ModuleName IntuneScriptLab -Exactly -Times 1 -ParameterFilter {
                $User -eq 'AzureAD\IslVerylongdisplayna' -and $Password -eq 'pw' -and $null -eq $Principal
            }
        }

        It 'says that a stored-password task does not start for an Entra account, right or no right (VM 125)' {
            # With the account granted "Log on as a batch job" for the test, the task still sat
            # Ready with 0x00041303, so the usual hint about the right would send someone the wrong way
            Mock Resolve-IslAccount -ModuleName IntuneScriptLab {
                [pscustomobject]@{ Name = 'AzureAD\IslVerylongdisplayna'; Sid = 'S-1-12-1-1-2-3-4' }
            }
            Mock Get-IslLogonSession -ModuleName IntuneScriptLab { @() }
            Mock Start-ScheduledTask -ModuleName IntuneScriptLab { }
            Mock Get-ScheduledTaskInfo -ModuleName IntuneScriptLab { [pscustomobject]@{ LastTaskResult = 267011 } }
            $launchSplat = $script:LaunchSplat.Clone()
            $launchSplat.Credential = [pscredential]::new('someone@contoso.com', $script:Credential.Password)
            $failure = { Invoke-Process $launchSplat } | Should-Throw
            $failure.Exception.Message | Should-BeLikeString ('*someone@contoso.com did not start: 0x00041303 ' +
                '(the scheduler never launched it: a stored-password task did not start for a Microsoft Entra ' +
                'account*sign the account in and run while it holds a session)')
            $failure.Exception.Message | Should-NotBeLikeString '*grant it in the local security policy*'
        }

        It 'does not take another account''s session for a sign-in name that only looks like it' {
            # The part before the @ of one account can be the Windows name of another
            Mock Resolve-IslAccount -ModuleName IntuneScriptLab {
                [pscustomobject]@{ Name = 'AzureAD\SomeoneElse'; Sid = 'S-1-12-1-1-2-3-4' }
            }
            Mock Get-IslLogonSession -ModuleName IntuneScriptLab {
                [pscustomobject]@{ UserName = 'isl-user'; Domain = 'LAB'; Sid = 'S-1-5-21-1-2-3-1001'; Id = 2 }
            }
            $launchSplat = $script:LaunchSplat.Clone()
            $launchSplat.Credential = [pscredential]::new('isl-user@lab.local', $script:Credential.Password)
            (Invoke-Process $launchSplat).LogonType | Should-Be 'Password'
        }

        It 'reports a logon the scheduler refuses instead of waiting for the timeout (VM 125, isl-user)' {
            Mock Get-IslLogonSession -ModuleName IntuneScriptLab { @() }
            Mock Start-ScheduledTask -ModuleName IntuneScriptLab { }
            Mock Get-ScheduledTaskInfo -ModuleName IntuneScriptLab {
                [pscustomobject]@{ LastTaskResult = 2147943785 }
            }
            $failure = { Invoke-Process $script:LaunchSplat } | Should-Throw
            # By the module's clock: it read the refusal, not the 30-second timeout of the run
            ($script:Clock - [datetime]'2026-01-01T00:00:00').TotalSeconds | Should-BeLessThan 10
            $failure.Exception.Message |
                Should-BeLikeString '*LAB\isl-user did not start: 0x80070569*Log on as a batch job*'
            $failure.FullyQualifiedErrorId | Should-BeLikeString 'ScheduledTaskNotStarted,*'
            Should-Invoke Unregister-ScheduledTask -ModuleName IntuneScriptLab -Exactly -Times 1
        }

        It 'reports a stored-password task the scheduler never launches, within seconds (VM 125, isl-user)' {
            Mock Get-IslLogonSession -ModuleName IntuneScriptLab { @() }
            Mock Start-ScheduledTask -ModuleName IntuneScriptLab { }
            # The task sits Ready with "has not run yet" (267011) and no error anywhere
            Mock Get-ScheduledTaskInfo -ModuleName IntuneScriptLab {
                [pscustomobject]@{ LastTaskResult = 267011 }
            }
            $failure = { Invoke-Process $script:LaunchSplat } | Should-Throw
            # By the module's clock: about five seconds of a task sitting Ready, not the 30-second
            # timeout of the run
            $waited = ($script:Clock - [datetime]'2026-01-01T00:00:00').TotalSeconds
            $waited | Should-BeGreaterThan 4
            $waited | Should-BeLessThan 15
            $failure.Exception.Message |
                Should-BeLikeString '*LAB\isl-user did not start: 0x00041303*never launched*Log on as a batch job*'
            Should-Invoke Unregister-ScheduledTask -ModuleName IntuneScriptLab -Exactly -Times 1
        }

        It 'names the account in the elevation message when the registration is refused' {
            Mock Get-IslLogonSession -ModuleName IntuneScriptLab { @() }
            Mock Register-ScheduledTask -ModuleName IntuneScriptLab { throw 'Access is denied.' }
            $failure = { Invoke-Process $script:LaunchSplat } | Should-Throw
            $failure.Exception.Message |
                Should-BeLikeString '*Running as LAB\isl-user*run elevated*Access is denied*'
        }
    }
}
