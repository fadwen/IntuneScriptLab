#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The password of a -Credential goes to the Task Scheduler and nowhere else (SEC-06, TST-43). A
    run as another account is driven from Invoke-IntunePlatformScriptTest down to the scheduled
    task, with the task cmdlets faked at that boundary, for an account without a session, which is
    the case that hands the password over. Every stream is captured with -Verbose on, and with
    -Debug on PowerShell 7 (Windows PowerShell 5.1 makes -Debug Inquire, which a test host cannot
    answer, so its debug stream is not read). The password must be in none of them, in no error,
    in no part of the result and in no file the run leaves behind; the task registration must be
    the one call that receives it.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')

    function script:Invoke-RunAsAccount {
        <#
        .SYNOPSIS
            Runs a platform script test as another account and captures everything it writes.

        .DESCRIPTION
            Calls Invoke-IntunePlatformScriptTest with the test's credential, -Verbose and, on
            PowerShell 7, -Debug, with every stream redirected to the output, and returns what came
            out as text: each object as JSON, each error with its message, its target and the
            message of every inner exception, and each other record as text. A terminating error is
            caught and added the same way.

        .EXAMPLE
            $captured = Invoke-RunAsAccount

            Returns the text of everything the run wrote.

        .INPUTS
            None.

        .OUTPUTS
            System.String. One string for each object or record.
        #>
        [CmdletBinding()]
        [OutputType([string])]
        param()

        $testSplat = @{
            Path = $script:ScriptPath; Architecture = 'x64'; Context = 'User'
            Credential = $script:Credential; TimeoutSeconds = 30
            Verbose = $true; InformationAction = 'Continue'; WarningAction = 'Continue'
            ErrorAction = 'Continue'
        }
        # -Debug is Continue from PowerShell 6 on. Windows PowerShell 5.1 makes it Inquire, which asks
        # at every ShouldProcess and fails in a host that cannot ask
        if ($PSVersionTable.PSVersion -ge [version]'6.0') {
            $testSplat['Debug'] = $true
        }
        $records = try {
            Invoke-IntunePlatformScriptTest @testSplat *>&1
        } catch {
            $_
        }
        foreach ($record in $records) {
            if ($record -is [System.Management.Automation.ErrorRecord]) {
                $exception = $record.Exception
                $messages = while ($null -ne $exception) {
                    $exception.Message
                    $exception = $exception.InnerException
                }
                "$record | $($messages -join ' | ') | $($record.TargetObject)"
            } elseif ($record -is [System.Management.Automation.InformationalRecord] -or
                $record -is [System.Management.Automation.InformationRecord]) {
                "$record"
            } else {
                $record | ConvertTo-Json -Depth 6 -Compress
            }
        }
    }
}

Describe 'The password of -Credential' -Tag 'Unit', 'Security' {

    BeforeEach {
        # A password made for the run, so that no other text can hold it by chance
        $script:Secret = "Isl-$([guid]::NewGuid().ToString('N'))"
        $secure = [securestring]::new()
        foreach ($char in $script:Secret.ToCharArray()) { $secure.AppendChar($char) }
        $script:Credential = [pscredential]::new('LAB\isl-user', $secure)
        $script:ScriptPath = New-TestScript 'Run.ps1' "'ran'; exit 0" -Bom

        # The run folder goes under ProgramData, pointed at the test's own drive
        $script:SavedProgramData = $env:ProgramData
        $env:ProgramData = Join-Path $TestDrive "programdata-$([guid]::NewGuid().ToString('N'))"
        Mock Grant-IslFolderAccess -ModuleName IntuneScriptLab { }
        # The account does not exist here and holds no session: the stored-password task
        Mock Resolve-IslAccount -ModuleName IntuneScriptLab { }
        Mock Get-IslLogonSession -ModuleName IntuneScriptLab { @() }
        Mock Unregister-ScheduledTask -ModuleName IntuneScriptLab { }
        Mock Stop-ScheduledTask -ModuleName IntuneScriptLab { }
        Mock Get-ScheduledTask -ModuleName IntuneScriptLab { [pscustomobject]@{ State = 'Ready' } }
        Mock Get-ScheduledTaskInfo -ModuleName IntuneScriptLab { [pscustomobject]@{ LastTaskResult = 267009 } }
        # What the task's wrapper would write into the run folder
        Mock Start-ScheduledTask -ModuleName IntuneScriptLab {
            # The task is named after the run folder, which is directly under ProgramData
            $folder = Join-Path $env:ProgramData $TaskName.Substring('IntuneScriptLab-'.Length)
            [IO.File]::WriteAllText((Join-Path $folder 'stdout.txt'), "ran`r`n")
            [IO.File]::WriteAllText((Join-Path $folder 'stderr.txt'), '')
            [IO.File]::WriteAllText((Join-Path $folder 'exitcode.txt'), "0`r`n")
        }
    }

    AfterEach {
        $env:ProgramData = $script:SavedProgramData
    }

    It 'goes to the task registration, and only there' {
        Mock Register-ScheduledTask -ModuleName IntuneScriptLab { }

        $captured = @(Invoke-RunAsAccount)

        Should-Invoke Register-ScheduledTask -ModuleName IntuneScriptLab -Times 1 -Exactly -ParameterFilter {
            $Password -eq $script:Secret -and "$($Action.Arguments)" -notlike "*$($script:Secret)*" -and
            "$($Action.Execute)" -notlike "*$($script:Secret)*" -and $User -eq 'LAB\isl-user'
        }
        $captured.Count | Should-BeGreaterThan 0
        $captured -join "`n" | Should-BeLikeString '*"RunState":*'
        ($captured -join "`n").Contains($script:Secret) | Should-BeFalse
    }

    It 'is in no file the run leaves behind' {
        Mock Register-ScheduledTask -ModuleName IntuneScriptLab { }

        $null = Invoke-RunAsAccount

        # A run as another account writes only under ProgramData, which the test points at its own
        # drive, so that is the whole of what it can leave
        $left = @(Get-ChildItem -LiteralPath $env:ProgramData -Recurse -File -ErrorAction SilentlyContinue)
        $holding = @($left | Where-Object {
                [System.IO.File]::ReadAllText($_.FullName).Contains($script:Secret)
            })
        $holding | Should-BeCollection -Count 0
        # The run folder itself is gone, with the copy and the task's output in it
        $runs = @(Get-ChildItem -LiteralPath $env:ProgramData -Filter 'IntuneScriptLabRun-*' -Directory)
        $runs | Should-BeCollection -Count 0
    }

    It 'is not in the error when the Task Scheduler refuses the task' {
        Mock Register-ScheduledTask -ModuleName IntuneScriptLab {
            throw [System.UnauthorizedAccessException]::new('Access is denied.')
        }

        $captured = @(Invoke-RunAsAccount)

        $captured -join "`n" | Should-BeLikeString '*Running as LAB\isl-user registers a scheduled task*'
        ($captured -join "`n").Contains($script:Secret) | Should-BeFalse
    }

    It 'is not in the error when the task does not start' {
        Mock Register-ScheduledTask -ModuleName IntuneScriptLab { }
        Mock Start-ScheduledTask -ModuleName IntuneScriptLab { }
        # 0x80070569: the account lacks the batch logon right a stored-password task needs
        Mock Get-ScheduledTaskInfo -ModuleName IntuneScriptLab {
            [pscustomobject]@{ LastTaskResult = [uint32]2147943785 }
        }

        $captured = @(Invoke-RunAsAccount)

        $captured -join "`n" | Should-BeLikeString '*did not start: 0x80070569*'
        ($captured -join "`n").Contains($script:Secret) | Should-BeFalse
    }
}
