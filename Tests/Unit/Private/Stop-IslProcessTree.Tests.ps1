#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The cleanup after a run that timed out, against real processes: a cmd.exe that runs ping.exe is
    the tree. The case that matters most is the process that is already gone, under an error
    preference of Stop: on Windows PowerShell 5.1 the call-operator form of this cleanup ended the
    caller with taskkill's "not found" line.
#>

BeforeAll {
    $moduleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $moduleRoot) {
        Import-Module (Join-Path $moduleRoot 'IntuneScriptLab.psd1') -Force
    }

    function Start-TestProcessTree {
        <#
        .SYNOPSIS
            Starts cmd.exe running ping.exe for two minutes and returns the ids of both.

        .DESCRIPTION
            A real tree of two processes, the parent and the child it started, for the tests that
            end a tree. Ends with ChildProcessNotStarted when ping.exe has not appeared within 15
            seconds.

        .EXAMPLE
            $parentId, $childId = Start-TestProcessTree

            Starts the tree and keeps the id of each process.

        .INPUTS
            None.

        .OUTPUTS
            System.Int32. The id of cmd.exe, then the id of ping.exe.
        #>
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Starts two short-lived processes that the test ends itself.')]
        [CmdletBinding()]
        [OutputType([int])]
        param()

        $startParameters = @{
            FilePath = Join-Path -Path $env:WINDIR -ChildPath 'System32\cmd.exe'
            ArgumentList = '/d', '/c', 'ping.exe -n 120 127.0.0.1 > nul'
            WindowStyle = 'Hidden'
            PassThru = $true
        }
        $parent = Start-Process @startParameters
        $child = $null
        $deadline = (Get-Date).AddSeconds(15)
        while ($null -eq $child -and (Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 200
            $child = Get-CimInstance -ClassName Win32_Process -Filter "ParentProcessId = $($parent.Id)" |
                Where-Object { $_.Name -eq 'PING.EXE' } | Select-Object -First 1
        }
        if ($null -eq $child) {
            $exception = [System.TimeoutException]::new('cmd.exe did not start ping.exe within 15 seconds.')
            $category = [System.Management.Automation.ErrorCategory]::OperationTimeout
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception, 'ChildProcessNotStarted', $category, $parent.Id)
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
        $parent.Id
        [int]$child.ProcessId
    }

    function Wait-ProcessGone {
        <#
        .SYNOPSIS
            Waits up to ten seconds for processes to end and returns the ids still running.

        .DESCRIPTION
            A process that was ended can take a moment to leave the process list, so the test
            waits for that instead of reading the list once.

        .PARAMETER Id
            The ids of the processes to wait for.

        .EXAMPLE
            Wait-ProcessGone -Id $parentId, $childId

            Returns nothing once both processes have ended, or the ids still running after ten
            seconds.

        .INPUTS
            None.

        .OUTPUTS
            System.Int32. The ids of the processes that are still running.
        #>
        [CmdletBinding()]
        [OutputType([int])]
        param(
            [Parameter(Mandatory)]
            [int[]]$Id
        )

        $deadline = (Get-Date).AddSeconds(10)
        do {
            $running = @(Get-Process -Id $Id -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
            if ($running.Count -gt 0) {
                Start-Sleep -Milliseconds 200
            }
        } while ($running.Count -gt 0 -and (Get-Date) -lt $deadline)
        $running
    }
}

Describe 'Stop-IslProcessTree' -Tag 'Unit', 'Private' {

    Context 'Parameter Validation' {
        It 'declares ProcessId as mandatory and supports -WhatIf' {
            InModuleScope IntuneScriptLab {
                $command = Get-Command -Name Stop-IslProcessTree
                $command | Should-HaveParameter -ParameterName 'ProcessId' -Type ([int]) -Mandatory
                $command | Should-HaveParameter -ParameterName 'WhatIf'
            }
        }
    }

    Context 'Core Functionality' {
        It 'ends the process and the process it started' {
            $tree = @(Start-TestProcessTree)
            try {
                InModuleScope IntuneScriptLab -Parameters @{ ProcessId = $tree[0] } {
                    Stop-IslProcessTree -ProcessId $ProcessId -Confirm:$false -ErrorAction Stop
                }

                @(Wait-ProcessGone -Id $tree) | Should-BeCollection @()
            } finally {
                Get-Process -Id $tree -ErrorAction SilentlyContinue | Stop-Process -Force
            }
        }

        It 'ends nothing under -WhatIf' {
            $tree = @(Start-TestProcessTree)
            try {
                InModuleScope IntuneScriptLab -Parameters @{ ProcessId = $tree[0] } {
                    Stop-IslProcessTree -ProcessId $ProcessId -WhatIf
                }

                @(Get-Process -Id $tree -ErrorAction SilentlyContinue).Count | Should-Be 2
            } finally {
                Get-Process -Id $tree -ErrorAction SilentlyContinue | Stop-Process -Force
            }
        }
    }

    Context 'Error Handling' {
        It 'neither fails nor warns for a process that is already gone, under an error preference of Stop' {
            $tree = @(Start-TestProcessTree)
            Get-Process -Id $tree -ErrorAction SilentlyContinue | Stop-Process -Force
            @(Wait-ProcessGone -Id $tree) | Should-BeCollection @()

            InModuleScope IntuneScriptLab -Parameters @{ ProcessId = $tree[0] } {
                # The preference a CI step and a script started with -File give the module
                $ErrorActionPreference = 'Stop'
                $warnings = @()
                Stop-IslProcessTree -ProcessId $ProcessId -Confirm:$false -WarningVariable warnings 3>$null
                $warnings.Count | Should-Be 0
            }
        }

        It 'ends a timed-out run although the caller''s WhatIf preference is on' {
            # A module function sees a global $WhatIfPreference. If the cleanup obeyed it, the process
            # would go on, and the run would wait for it: here for the half minute that ping takes
            $parameters = @{
                FilePath = Join-Path -Path $env:WINDIR -ChildPath 'System32\cmd.exe'
                Arguments = '/d /c ping.exe -n 30 127.0.0.1 > nul'
                WorkingDirectory = $TestDrive
                WorkFolder = $TestDrive
                TimeoutSeconds = 2
            }
            InModuleScope IntuneScriptLab -Parameters @{ Parameters = $parameters } {
                $WhatIfPreference = $true
                $result = Invoke-IslProcess @Parameters
                $result.TimedOut | Should-BeTrue
                $result.Duration.TotalSeconds | Should-BeLessThan 15
            }
        }

        It 'lets a timed-out run end with its result under an error preference of Stop' {
            $parameters = @{
                FilePath = Join-Path -Path $env:WINDIR -ChildPath 'System32\cmd.exe'
                Arguments = '/d /c ping.exe -n 120 127.0.0.1 > nul'
                WorkingDirectory = $TestDrive
                WorkFolder = $TestDrive
                TimeoutSeconds = 2
            }
            InModuleScope IntuneScriptLab -Parameters @{ Parameters = $parameters } {
                $ErrorActionPreference = 'Stop'
                $result = Invoke-IslProcess @Parameters
                $result.TimedOut | Should-BeTrue
                $result.ExitCode | Should-BeNull
            }
        }
    }
}
