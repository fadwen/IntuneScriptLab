#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The Win32 app status mapping (detect, install or uninstall, detect) with the detection, the rule
    evaluation and the installer launch mocked. The install mock flips an environment variable that
    the detection mock reads, so the flow is the one Intune runs without any process starting; the
    uninstall mock clears it. Real installs are covered in Tests\Integration.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
    $script:FileRule = @{ Type = 'File'; Path = 'C:\Fixtures'; FileOrFolderName = 'present.txt'
        OperationType = 'exists' }
    $script:MissingRule = @{ Type = 'File'; Path = 'C:\Fixtures'; FileOrFolderName = 'missing.txt'
        OperationType = 'exists' }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\ISL_TEST_INSTALLED, Env:\ISL_TEST_MARKERS -ErrorAction SilentlyContinue
}

Describe 'Invoke-IntuneWin32AppTest' -Tag 'Unit', 'Public' {

    BeforeEach {
        $env:ISL_TEST_INSTALLED = ''
        $script:Fixture = New-Win32Fixture 'app' '# mocked' '# mocked'
        Mock Invoke-IntuneDetectionTest -ModuleName IntuneScriptLab {
            $installed = $env:ISL_TEST_INSTALLED -eq '1'
            [pscustomobject]@{
                Detected = $installed; TimedOut = $false; ExitCode = if ($installed) { 0 } else { 1 }
                Reason = if ($installed) { 'Exit 0 with stdout and no stderr' } else { 'Exit code 1' }
            }
        }
        # A rule on missing.txt is never met; any other rule is met
        Mock Test-IntuneWin32Rule -ModuleName IntuneScriptLab {
            $met = $Rule.FileOrFolderName -ne 'missing.txt'
            [pscustomobject]@{
                Met = $met; Kind = 'File'; Operation = 'Exists'; RuleType = $RuleType
                Reason = if ($met) { 'exists' } else { 'C:\Fixtures\missing.txt does not exist' }
            }
        }
        # The command carries its own exit code: "setup.exe /exit 3010"; an install marks the app
        # installed, an uninstall marks it gone
        Mock Invoke-IslProcess -ModuleName IntuneScriptLab {
            $code = if ($Arguments -match '/exit (\d+)') { [int]$Matches[1] } else { 0 }
            if ($code -in 0, 1707, 3010, 1641) {
                $env:ISL_TEST_INSTALLED = if ($Arguments -match 'uninstall') { '' } else { '1' }
            }
            [pscustomobject]@{ ExitCode = $code; TimedOut = $false; StdOut = "installer $code"; StdErr = ''
                Duration = [timespan]::Zero }
        }
    }

    Context 'Parameter Validation' {
        It 'needs a detection script or detection rules, the content folder and the intent command' {
            $command = Get-Command Invoke-IntuneWin32AppTest
            $command.Parameters['ContentPath'].Attributes.Mandatory | Should-ContainCollection $true
            { Invoke-IntuneWin32AppTest -ContentPath $script:Fixture.Content -InstallCommand 'setup.exe' } |
                Should-Throw -ExceptionMessage '*-DetectionPath*-DetectionRule*'
            $intuneWin32AppTestSplat = @{
                DetectionPath = $script:Fixture.Detection
                ContentPath   = $script:Fixture.Content
            }
            { Invoke-IntuneWin32AppTest @intuneWin32AppTestSplat } |
                Should-Throw -ExceptionMessage '*-InstallCommand*'
            $intuneWin32AppTestSplat2 = @{
                DetectionPath  = $script:Fixture.Detection
                Intent         = 'Uninstall'
                ContentPath    = $script:Fixture.Content
                InstallCommand = 'setup.exe'
            }
            { Invoke-IntuneWin32AppTest @intuneWin32AppTestSplat2 } |
                Should-Throw -ExceptionMessage '*-UninstallCommand*'
        }

        It 'defaults to the 64-bit host, as the portal does for Win32 detection' {
            $intuneWin32AppTestSplat = @{
                DetectionPath  = $script:Fixture.Detection
                ContentPath    = $script:Fixture.Content
                InstallCommand = 'setup.exe /exit 0'
            }
            $result = Invoke-IntuneWin32AppTest @intuneWin32AppTestSplat
            $result.Architecture | Should-Be 'x64'
            Should-Invoke Invoke-IntuneDetectionTest -ModuleName IntuneScriptLab -ParameterFilter {
                $Architecture -eq 'x64'
            }
        }

        It 'fails when the content folder does not exist' {
            $missing = Join-Path $TestDrive 'nowhere'
            $intuneWin32AppTestSplat = @{
                DetectionPath  = $script:Fixture.Detection
                ContentPath    = $missing
                InstallCommand = 'setup.exe'
            }
            { Invoke-IntuneWin32AppTest @intuneWin32AppTestSplat } | Should-Throw
        }
    }

    Context 'Core Functionality' {
        It 'reports Installed and never runs the installer when the detection already passes' {
            $env:ISL_TEST_INSTALLED = '1'
            $intuneWin32AppTestSplat = @{
                DetectionPath  = $script:Fixture.Detection
                ContentPath    = $script:Fixture.Content
                InstallCommand = 'setup.exe /exit 0'
            }
            $result = Invoke-IntuneWin32AppTest @intuneWin32AppTestSplat
            $result.Status | Should-Be 'Installed'
            $result.Intent | Should-Be 'Install'
            $result.Install | Should-BeNull
            Should-Invoke Invoke-IslProcess -ModuleName IntuneScriptLab -Exactly -Times 0
        }

        It 'installs through a 32-bit cmd.exe from a copy of the content, then detects' {
            $intuneWin32AppTestSplat = @{
                DetectionPath  = $script:Fixture.Detection
                ContentPath    = $script:Fixture.Content
                InstallCommand = 'setup.exe /exit 0'
            }
            $result = Invoke-IntuneWin32AppTest @intuneWin32AppTestSplat
            $result.Status | Should-Be 'Installed after install'
            $result.Install.ExitCode | Should-Be 0
            $result.Install.Command | Should-Be 'setup.exe /exit 0'
            $result.PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.Win32AppResult'
            Should-Invoke Invoke-IslProcess -ModuleName IntuneScriptLab -Exactly -Times 1 -ParameterFilter {
                $FilePath -like '*\SysWOW64\cmd.exe' -and $Arguments -eq '/C "setup.exe /exit 0"' -and
                $LauncherBitness -eq 'x86' -and $WorkingDirectory -ne $script:Fixture.Content -and
                $WorkingDirectory -like '*IntuneScriptLab*content'
            }
            Should-Invoke Invoke-IntuneDetectionTest -ModuleName IntuneScriptLab -Exactly -Times 2
        }

        It 'reports Not detected after install with the 0x87D1041C hint when detection still fails' {
            Mock Invoke-IslProcess -ModuleName IntuneScriptLab {
                [pscustomobject]@{
                    ExitCode = 0; TimedOut = $false; StdOut = ''; StdErr = ''; Duration = [timespan]::Zero
                }
            }
            $intuneWin32AppTestSplat = @{
                DetectionPath  = $script:Fixture.Detection
                ContentPath    = $script:Fixture.Content
                InstallCommand = 'setup.exe /exit 0'
            }
            $result = Invoke-IntuneWin32AppTest @intuneWin32AppTestSplat
            $result.Status | Should-Be 'Not detected after install'
            $result.Warnings -join ' ' | Should-BeLikeString '*0x87D1041C*'
        }

        It 'maps the return codes: <Code> is <Status>' -ForEach @(
            @{ Code = 7;    Status = 'Install failed (exit 7)' }
            @{ Code = 1618; Status = 'Retry' }
            @{ Code = 1707; Status = 'Installed after install' }
        ) {
            $intuneWin32AppTestSplat = @{
                DetectionPath  = $script:Fixture.Detection
                ContentPath    = $script:Fixture.Content
                InstallCommand = "setup.exe /exit $Code"
            }
            $result = Invoke-IntuneWin32AppTest @intuneWin32AppTestSplat
            $result.Status | Should-Be $Status
        }

        It 'treats 3010 and 1641 as success with a pending reboot warning' {
            $intuneWin32AppTestSplat = @{
                DetectionPath  = $script:Fixture.Detection
                ContentPath    = $script:Fixture.Content
                InstallCommand = 'setup.exe /exit 3010'
            }
            $result = Invoke-IntuneWin32AppTest @intuneWin32AppTestSplat
            $result.Status | Should-Be 'Installed after install'
            $result.Warnings -join ' ' | Should-BeLikeString '*3010*softReboot*'
            $env:ISL_TEST_INSTALLED = ''
            $intuneWin32AppTestSplat2 = @{
                DetectionPath  = $script:Fixture.Detection
                ContentPath    = $script:Fixture.Content
                InstallCommand = 'setup.exe /exit 1641'
            }
            $result = Invoke-IntuneWin32AppTest @intuneWin32AppTestSplat2
            $result.Warnings -join ' ' | Should-BeLikeString '*1641*hardReboot*'
        }

        It 'honours a custom return code table' {
            $intuneWin32AppTestSplat = @{
                DetectionPath  = $script:Fixture.Detection
                ContentPath    = $script:Fixture.Content
                InstallCommand = 'setup.exe /exit 7'
                ReturnCodes    = @{ 7 = 'retry' }
            }
            $result = Invoke-IntuneWin32AppTest @intuneWin32AppTestSplat
            $result.Status | Should-Be 'Retry'
        }

        It 'warns that a user install context is never installed by a device-group assignment (W32-USER-INSTALL)' {
            $env:ISL_TEST_INSTALLED = '1'
            $intuneWin32AppTestSplat = @{
                DetectionPath  = $script:Fixture.Detection
                ContentPath    = $script:Fixture.Content
                InstallCommand = 'setup.exe /exit 0'
                InstallContext = 'User'
            }
            $result = Invoke-IntuneWin32AppTest @intuneWin32AppTestSplat
            $result.Warnings -join ' ' | Should-BeLikeString '*userless check-in*Applicability 1011*'
            $result.Status | Should-Be 'Installed'
        }

        It 'warns that powershell.exe in the install command is the 32-bit host' {
            $intuneWin32AppTestSplat = @{
                DetectionPath  = $script:Fixture.Detection
                ContentPath    = $script:Fixture.Content
                InstallCommand = 'powershell.exe -ExecutionPolicy Bypass -File install.ps1'
            }
            $result = Invoke-IntuneWin32AppTest @intuneWin32AppTestSplat
            $result.Warnings -join ' ' | Should-BeLikeString '*powershell.exe*32-bit host*'
        }

        It 'warns about powershell.exe inside the batch file the install command names' {
            Set-Content -Path (Join-Path $script:Fixture.Content 'install.cmd') -Encoding ascii -Value @(
                '@echo off'
                'powershell.exe -NoProfile -ExecutionPolicy Bypass -File install.ps1'
            )
            $intuneWin32AppTestSplat = @{
                DetectionPath  = $script:Fixture.Detection
                ContentPath    = $script:Fixture.Content
                InstallCommand = 'install.cmd'
            }
            $result = Invoke-IntuneWin32AppTest @intuneWin32AppTestSplat
            $result.Warnings -join ' ' |
                Should-BeLikeString '*powershell.exe in install.cmd (line 2)*32-bit host*'
        }

        It 'does not warn when the batch file the install command names has no powershell call' {
            Set-Content -Path (Join-Path $script:Fixture.Content 'install.cmd') -Encoding ascii -Value @(
                '@echo off'
                'setup.exe /S'
            )
            $intuneWin32AppTestSplat = @{
                DetectionPath  = $script:Fixture.Detection
                ContentPath    = $script:Fixture.Content
                InstallCommand = '"install.cmd" /quiet'
            }
            $result = Invoke-IntuneWin32AppTest @intuneWin32AppTestSplat
            $result.Warnings -join ' ' | Should-NotBeLikeString '*32-bit host*'
        }

        It 'passes -EnforceSignatureCheck to every detection run' {
            $intuneWin32AppTestSplat = @{
                DetectionPath         = $script:Fixture.Detection
                ContentPath           = $script:Fixture.Content
                InstallCommand        = 'setup.exe /exit 0'
                EnforceSignatureCheck = $true
            }
            $result = Invoke-IntuneWin32AppTest @intuneWin32AppTestSplat
            $result.Status | Should-Be 'Installed after install'
            $invokeSplat = @{ CommandName = 'Invoke-IntuneDetectionTest'; ModuleName = 'IntuneScriptLab' }
            Should-Invoke @invokeSplat -Exactly -Times 2 -ParameterFilter { $EnforceSignatureCheck -eq $true }
        }
    }

    Context 'Detection rules (all must match)' {
        It 'counts the app installed when every rule is met and no script is given' {
            $intuneWin32AppTestSplat = @{
                DetectionRule  = $script:FileRule, $script:FileRule
                ContentPath    = $script:Fixture.Content
                InstallCommand = 'setup.exe /exit 0'
            }
            $result = Invoke-IntuneWin32AppTest @intuneWin32AppTestSplat
            $result.Status | Should-Be 'Installed'
            $result.PreDetection | Should-BeNull
            @($result.PreRules).Count | Should-Be 2
            Should-Invoke Test-IntuneWin32Rule -ModuleName IntuneScriptLab -Exactly -Times 2 -ParameterFilter {
                $RuleType -eq 'Detection'
            }
            Should-Invoke Invoke-IntuneDetectionTest -ModuleName IntuneScriptLab -Exactly -Times 0
        }

        It 'runs the install when one of two rules is not met, and says which (W32-MULTI-ONEFALSE)' {
            $intuneWin32AppTestSplat = @{
                DetectionRule  = $script:FileRule, $script:MissingRule
                ContentPath    = $script:Fixture.Content
                InstallCommand = 'setup.exe /exit 0'
            }
            $result = Invoke-IntuneWin32AppTest @intuneWin32AppTestSplat
            # The install cannot make missing.txt appear, so the post-detection fails the same way
            $result.Status | Should-Be 'Not detected after install'
            $result.Warnings -join ' ' | Should-BeLikeString '*Pre detection rule not met*missing.txt*'
            Should-Invoke Invoke-IslProcess -ModuleName IntuneScriptLab -Exactly -Times 1
        }

        It 'requires the script and the rules to agree when both are given' {
            $env:ISL_TEST_INSTALLED = '1'
            $intuneWin32AppTestSplat = @{
                DetectionPath  = $script:Fixture.Detection
                DetectionRule  = $script:MissingRule
                ContentPath    = $script:Fixture.Content
                InstallCommand = 'setup.exe /exit 0'
            }
            $result = Invoke-IntuneWin32AppTest @intuneWin32AppTestSplat
            $result.Status | Should-Be 'Not detected after install'
            $result.PreDetection.Detected | Should-BeTrue
            $result.PreRules[0].Met | Should-BeFalse
        }
    }

    Context 'Uninstall intent (W32-UNINSTALL)' {
        It 'reports Not installed and runs nothing when the detection already fails' {
            $intuneWin32AppTestSplat = @{
                DetectionPath    = $script:Fixture.Detection
                Intent           = 'Uninstall'
                ContentPath      = $script:Fixture.Content
                UninstallCommand = 'setup.exe /uninstall /exit 0'
            }
            $result = Invoke-IntuneWin32AppTest @intuneWin32AppTestSplat
            $result.Status | Should-Be 'Not installed'
            $result.Uninstall | Should-BeNull
            Should-Invoke Invoke-IslProcess -ModuleName IntuneScriptLab -Exactly -Times 0
        }

        It 'detects, runs the uninstall command from the content copy, and detects again: Uninstalled' {
            $env:ISL_TEST_INSTALLED = '1'
            $intuneWin32AppTestSplat = @{
                DetectionPath    = $script:Fixture.Detection
                Intent           = 'Uninstall'
                ContentPath      = $script:Fixture.Content
                UninstallCommand = 'setup.exe /uninstall /exit 0'
            }
            $result = Invoke-IntuneWin32AppTest @intuneWin32AppTestSplat
            $result.Status | Should-Be 'Uninstalled'
            $result.Intent | Should-Be 'Uninstall'
            $result.Uninstall.Command | Should-Be 'setup.exe /uninstall /exit 0'
            $result.Uninstall.Phase | Should-Be 'uninstall'
            $result.Install | Should-BeNull
            $result.PostDetection.Detected | Should-BeFalse
            Should-Invoke Invoke-IntuneDetectionTest -ModuleName IntuneScriptLab -Exactly -Times 2
        }

        It 'reports Still detected after uninstall when the detection keeps saying installed' {
            $env:ISL_TEST_INSTALLED = '1'
            Mock Invoke-IslProcess -ModuleName IntuneScriptLab {
                [pscustomobject]@{
                    ExitCode = 0; TimedOut = $false; StdOut = ''; StdErr = ''; Duration = [timespan]::Zero
                }
            }
            $intuneWin32AppTestSplat = @{
                DetectionPath    = $script:Fixture.Detection
                Intent           = 'Uninstall'
                ContentPath      = $script:Fixture.Content
                UninstallCommand = 'setup.exe /uninstall'
            }
            $result = Invoke-IntuneWin32AppTest @intuneWin32AppTestSplat
            $result.Status | Should-Be 'Still detected after uninstall'
            $result.Warnings -join ' ' | Should-BeLikeString '*still reports installed*'
        }

        It 'maps an uninstall exit code that is not a success code to Uninstall failed' {
            $env:ISL_TEST_INSTALLED = '1'
            $intuneWin32AppTestSplat = @{
                DetectionPath    = $script:Fixture.Detection
                Intent           = 'Uninstall'
                ContentPath      = $script:Fixture.Content
                UninstallCommand = 'setup.exe /uninstall /exit 9'
            }
            $result = Invoke-IntuneWin32AppTest @intuneWin32AppTestSplat
            $result.Status | Should-Be 'Uninstall failed (exit 9)'
        }
    }

    Context 'Dependencies and supersedence (W32-DEP-*, W32-DEPD-*, W32-SUP-*)' {
        BeforeEach {
            # Several apps in one run, so the state is a marker file per app: the detection mock
            # looks for <fixture name>.marker, the installer mock creates (/mark) or removes
            # (/unmark) it, and refuses when a /needs marker is missing or a /needsabsent one exists
            $env:ISL_TEST_MARKERS = Join-Path $TestDrive 'markers'
            $null = New-Item -ItemType Directory -Path $env:ISL_TEST_MARKERS -Force
            Remove-Item (Join-Path $env:ISL_TEST_MARKERS '*.marker') -ErrorAction SilentlyContinue
            $script:Parent = New-Win32Fixture 'parent' '# mocked' '# mocked'
            $script:Child = New-Win32Fixture 'child' '# mocked' '# mocked'
            $script:Old = New-Win32Fixture 'old' '# mocked' '# mocked'
            Mock Invoke-IntuneDetectionTest -ModuleName IntuneScriptLab {
                $app = Split-Path (Split-Path $Path -Parent) -Leaf
                $installed = Test-Path (Join-Path $env:ISL_TEST_MARKERS "$app.marker")
                [pscustomobject]@{
                    Detected = $installed; TimedOut = $false; ExitCode = if ($installed) { 0 } else { 1 }
                    Reason = if ($installed) { "$app marker present" } else { "no $app marker" }
                }
            }
            Mock Invoke-IslProcess -ModuleName IntuneScriptLab {
                $markers = $env:ISL_TEST_MARKERS
                $code = if ($Arguments -match '/exit (\d+)') { [int]$Matches[1] } else { 0 }
                if ($Arguments -match '/needs (\S+)' -and -not (Test-Path "$markers\$($Matches[1]).marker")) {
                    $code = 99
                }
                if ($Arguments -match '/needsabsent (\S+)' -and (Test-Path "$markers\$($Matches[1]).marker")) {
                    $code = 98
                }
                if ($code -in 0, 1707, 3010, 1641) {
                    if ($Arguments -match '/mark (\S+)') {
                        $null = New-Item -ItemType File -Path "$markers\$($Matches[1]).marker" -Force
                    }
                    if ($Arguments -match '/unmark (\S+)') {
                        Remove-Item "$markers\$($Matches[1]).marker" -ErrorAction SilentlyContinue
                    }
                }
                [pscustomobject]@{ ExitCode = $code; TimedOut = $false; StdOut = "installer $code"; StdErr = ''
                    Duration = [timespan]::Zero }
            }
            $script:ParentSplat = @{
                DetectionPath  = $script:Parent.Detection
                ContentPath    = $script:Parent.Content
                InstallCommand = 'setup.exe /mark parent /needs child /exit 0'
            }
            $script:ChildApp = @{
                Name = 'Child'; DetectionPath = $script:Child.Detection; ContentPath = $script:Child.Content
                InstallCommand = 'setup.exe /mark child /exit 0'
            }
            $script:OldApp = @{
                Name = 'Old'; DetectionPath = $script:Old.Detection; ContentPath = $script:Old.Content
                UninstallCommand = 'setup.exe /unmark old /exit 0'
            }
        }

        It 'installs an autoInstall dependency first: child detect, install, detect, then the parent' {
            $result = Invoke-IntuneWin32AppTest @script:ParentSplat -DependsOn $script:ChildApp
            # The parent's installer refuses (/needs child) unless the child marker already exists
            $result.Status | Should-Be 'Installed after install'
            $result.Install.ExitCode | Should-Be 0
            @($result.Dependencies).Count | Should-Be 1
            $result.Dependencies[0].Name | Should-Be 'Child'
            $result.Dependencies[0].Relationship | Should-Be 'dependency (autoInstall)'
            $result.Dependencies[0].Status | Should-Be 'Installed after install'
            $result.Dependencies[0].PreDetection.Detected | Should-BeFalse
            $result.Dependencies[0].PostDetection.Detected | Should-BeTrue
            $result.Dependencies[0].Install.Command | Should-Be 'setup.exe /mark child /exit 0'
            $result.Dependencies[0].PSObject.TypeNames |
                Should-ContainCollection 'IntuneScriptLab.Win32RelatedResult'
            Should-Invoke Invoke-IslProcess -ModuleName IntuneScriptLab -Exactly -Times 2
            # parent pre, child pre, child post, parent post
            Should-Invoke Invoke-IntuneDetectionTest -ModuleName IntuneScriptLab -Exactly -Times 4
        }

        It 'leaves an installed dependency alone and installs the parent' {
            $null = New-Item -ItemType File -Path (Join-Path $env:ISL_TEST_MARKERS 'child.marker')
            $result = Invoke-IntuneWin32AppTest @script:ParentSplat -DependsOn $script:ChildApp
            $result.Status | Should-Be 'Installed after install'
            $result.Dependencies[0].Status | Should-Be 'Installed'
            $result.Dependencies[0].Install | Should-BeNull
            Should-Invoke Invoke-IslProcess -ModuleName IntuneScriptLab -Exactly -Times 1 -ParameterFilter {
                $Arguments -like '*mark parent*'
            }
        }

        It 'never runs the parent install when a detect-only dependency is absent (W32-DEPD-PARENT)' {
            $detectOnly = $script:ChildApp.Clone()
            $detectOnly.Type = 'detect'
            $result = Invoke-IntuneWin32AppTest @script:ParentSplat -DependsOn $detectOnly
            $result.Status | Should-Be 'Not installed (dependency)'
            $result.Install | Should-BeNull
            $result.Dependencies[0].Relationship | Should-Be 'dependency (detect)'
            $result.Dependencies[0].Status | Should-Be 'Not detected (detect-only dependency)'
            $result.Warnings -join ' ' |
                Should-BeLikeString '*1 or more dependent apps are configured to not automatically install*'
            Should-Invoke Invoke-IslProcess -ModuleName IntuneScriptLab -Exactly -Times 0
        }

        It 'stops at a dependency whose install fails, and says so' {
            $failing = $script:ChildApp.Clone()
            $failing.InstallCommand = 'setup.exe /mark child /exit 7'
            $result = Invoke-IntuneWin32AppTest @script:ParentSplat -DependsOn $failing
            $result.Status | Should-Be 'Not installed (dependency)'
            $result.Dependencies[0].Status | Should-Be 'Install failed (exit 7)'
            $result.Warnings -join ' ' |
                Should-BeLikeString '*Dependency Child (autoInstall): Install failed (exit 7)*'
            Should-Invoke Invoke-IslProcess -ModuleName IntuneScriptLab -Exactly -Times 1
        }

        It 'evaluates a dependency by rules and labels the unmet rule with the dependency name' {
            $byRule = @{ Name = 'Runtime'; DetectionRule = @($script:MissingRule) }
            $result = Invoke-IntuneWin32AppTest @script:ParentSplat -DependsOn $byRule
            # No InstallCommand on the entry: nothing can be run for it
            $result.Status | Should-Be 'Not installed (dependency)'
            $result.Dependencies[0].Status | Should-Be 'Not detected (no InstallCommand or ContentPath)'
            $result.Dependencies[0].PreDetection | Should-BeNull
            @($result.Dependencies[0].PreRules).Count | Should-Be 1
            $result.Warnings -join ' ' | Should-BeLikeString '*rule not met for dependency Runtime*missing.txt*'
        }

        It 'skips the dependencies when the parent is already detected' {
            $null = New-Item -ItemType File -Path (Join-Path $env:ISL_TEST_MARKERS 'parent.marker')
            $result = Invoke-IntuneWin32AppTest @script:ParentSplat -DependsOn $script:ChildApp
            $result.Status | Should-Be 'Installed'
            @($result.Dependencies).Count | Should-Be 0
            Should-Invoke Invoke-IntuneDetectionTest -ModuleName IntuneScriptLab -Exactly -Times 1
        }

        It 'leaves a superseded app in place for an update and installs the new one (W32-SUP-OLD-A)' {
            $null = New-Item -ItemType File -Path (Join-Path $env:ISL_TEST_MARKERS 'old.marker')
            $newSplat = $script:ParentSplat.Clone()
            $newSplat.InstallCommand = 'setup.exe /mark parent /exit 0'
            $result = Invoke-IntuneWin32AppTest @newSplat -Supersedes $script:OldApp
            $result.Status | Should-Be 'Installed after install'
            @($result.Superseded).Count | Should-Be 1
            $result.Superseded[0].Relationship | Should-Be 'supersedence (update)'
            $result.Superseded[0].Status | Should-Be 'Installed (left in place by update)'
            $result.Superseded[0].Uninstall | Should-BeNull
            Test-Path (Join-Path $env:ISL_TEST_MARKERS 'old.marker') | Should-BeTrue
            Should-Invoke Invoke-IslProcess -ModuleName IntuneScriptLab -Exactly -Times 1
        }

        It 'runs the old uninstall before the new install for a replace (W32-SUP-OLD-B)' {
            $null = New-Item -ItemType File -Path (Join-Path $env:ISL_TEST_MARKERS 'old.marker')
            $replace = $script:OldApp.Clone()
            $replace.Type = 'replace'
            $newSplat = $script:ParentSplat.Clone()
            # The new installer refuses (/needsabsent old) while the old marker still exists
            $newSplat.InstallCommand = 'setup.exe /mark parent /needsabsent old /exit 0'
            $result = Invoke-IntuneWin32AppTest @newSplat -Supersedes $replace
            $result.Status | Should-Be 'Installed after install'
            $result.Superseded[0].Relationship | Should-Be 'supersedence (replace)'
            $result.Superseded[0].Status | Should-Be 'Uninstalled'
            $result.Superseded[0].Uninstall.Phase | Should-Be 'uninstall'
            $result.Superseded[0].Uninstall.Command | Should-Be 'setup.exe /unmark old /exit 0'
            $result.Superseded[0].PostDetection.Detected | Should-BeFalse
            Test-Path (Join-Path $env:ISL_TEST_MARKERS 'old.marker') | Should-BeFalse
            Should-Invoke Invoke-IslProcess -ModuleName IntuneScriptLab -Exactly -Times 2
        }

        It 'reports a replace target that is not installed and runs no uninstall' {
            $replace = $script:OldApp.Clone()
            $replace.Type = 'replace'
            $newSplat = $script:ParentSplat.Clone()
            $newSplat.InstallCommand = 'setup.exe /mark parent /exit 0'
            $result = Invoke-IntuneWin32AppTest @newSplat -Supersedes $replace
            $result.Status | Should-Be 'Installed after install'
            $result.Superseded[0].Status | Should-Be 'Not installed'
            $result.Superseded[0].Uninstall | Should-BeNull
            @($result.Warnings).Count | Should-Be 0
        }

        It 'warns when a replace target survives its uninstall, and still installs' {
            $null = New-Item -ItemType File -Path (Join-Path $env:ISL_TEST_MARKERS 'old.marker')
            $replace = $script:OldApp.Clone()
            $replace.Type = 'replace'
            $replace.UninstallCommand = 'setup.exe /exit 0'
            $newSplat = $script:ParentSplat.Clone()
            $newSplat.InstallCommand = 'setup.exe /mark parent /exit 0'
            $result = Invoke-IntuneWin32AppTest @newSplat -Supersedes $replace
            $result.Status | Should-Be 'Installed after install'
            $result.Superseded[0].Status | Should-Be 'Still detected after uninstall'
            $result.Warnings -join ' ' | Should-BeLikeString '*Superseded app Old (replace): Still detected*'
        }

        It 'rejects a related app without a Name or without a detection' {
            $noName = @{ DetectionPath = $script:Child.Detection }
            { Invoke-IntuneWin32AppTest @script:ParentSplat -DependsOn $noName } |
                Should-Throw -ExceptionMessage '*needs a Name*'
            $noDetection = @{ Name = 'Old' }
            { Invoke-IntuneWin32AppTest @script:ParentSplat -Supersedes $noDetection } |
                Should-Throw -ExceptionMessage '*Old needs a DetectionPath*'
        }
    }

    Context 'Error Handling' {
        It 'reports TimedOut when the installer is killed and skips the post-detection' {
            Mock Invoke-IslProcess -ModuleName IntuneScriptLab {
                [pscustomobject]@{
                    ExitCode = $null; TimedOut = $true; StdOut = ''; StdErr = ''; Duration = [timespan]::Zero
                }
            }
            $intuneWin32AppTestSplat = @{
                DetectionPath         = $script:Fixture.Detection
                ContentPath           = $script:Fixture.Content
                InstallCommand        = 'setup.exe'
                InstallTimeoutSeconds = 1
            }
            $result = Invoke-IntuneWin32AppTest @intuneWin32AppTestSplat
            $result.Status | Should-Be 'TimedOut'
            $result.PostDetection | Should-BeNull
            Should-Invoke Invoke-IntuneDetectionTest -ModuleName IntuneScriptLab -Exactly -Times 1
        }

        It 'reports TimedOut when the pre-detection is killed' {
            Mock Invoke-IntuneDetectionTest -ModuleName IntuneScriptLab {
                [pscustomobject]@{ Detected = $false; TimedOut = $true; ExitCode = $null; Reason = 'Timed out' }
            }
            $intuneWin32AppTestSplat = @{
                DetectionPath  = $script:Fixture.Detection
                ContentPath    = $script:Fixture.Content
                InstallCommand = 'setup.exe'
            }
            $result = Invoke-IntuneWin32AppTest @intuneWin32AppTestSplat
            $result.Status | Should-Be 'TimedOut'
            $result.Install | Should-BeNull
        }
    }
}
