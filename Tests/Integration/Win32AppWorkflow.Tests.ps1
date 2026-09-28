#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The Win32 app flow (detect, install, detect) end to end: a real install.ps1 run through the
    32-bit cmd.exe from a copy of the content, and the statuses that follow from its exit code.
#>

#pester:no-parallel

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
    $script:Install = 'powershell.exe -ExecutionPolicy Bypass -File install.ps1'
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Win32 app workflow' -Tag 'Integration', 'EndToEnd', 'Runtime' {

    It 'reports Installed and skips the install when the detection passes' {
        $fixture = New-Win32Fixture 'a' 'exit 0' 'Write-Output "installed"; exit 0'
        $intuneWin32AppTestSplat = @{
            DetectionPath  = $fixture.Detection
            ContentPath    = $fixture.Content
            InstallCommand = $script:Install
            Architecture   = 'x86'
        }
        $result = Invoke-IntuneWin32AppTest @intuneWin32AppTestSplat
        $result.Status | Should-Be 'Installed'
        $result.Install | Should-BeNull
    }

    It 'installs from a copy of the content in a 32-bit process, then detects: Installed after install' {
        $fixture = New-Win32Fixture 'b' 'exit 0' 'exit 1'
        # install.ps1 records its bitness and working directory, and leaves the marker
        $installBody = ("[Environment]::Is64BitProcess.ToString() + '|' + (Get-Location).Path | " +
            "Set-Content -Path '$($fixture.Marker)'`nexit 0")
        $detectBody = "if (Test-Path '$($fixture.Marker)') { 'installed'; exit 0 } else { exit 1 }"
        Set-Win32FixtureScript -Fixture $fixture -InstallBody $installBody -DetectBody $detectBody
        $intuneWin32AppTestSplat = @{
            DetectionPath  = $fixture.Detection
            ContentPath    = $fixture.Content
            InstallCommand = $script:Install
            Architecture   = 'x86'
        }
        $result = Invoke-IntuneWin32AppTest @intuneWin32AppTestSplat
        $result.Status | Should-Be 'Installed after install'
        $result.Install.ExitCode | Should-Be 0
        $bitness, $cwd = (Get-Content $fixture.Marker -Raw).Trim() -split '\|'
        $bitness | Should-Be 'False'
        $cwd | Should-NotBe $fixture.Content
        $cwd | Should-BeLikeString '*IntuneScriptLab*content'
        $result.Warnings -join ' ' | Should-BeLikeString '*32-bit host*'
    }

    It 'reports Not detected after install when the install succeeds but detection still fails (0x87D1041C)' {
        $fixture = New-Win32Fixture 'c' 'exit 0' 'exit 0'
        $intuneWin32AppTestSplat = @{
            DetectionPath  = $fixture.Detection
            ContentPath    = $fixture.Content
            InstallCommand = $script:Install
            Architecture   = 'x86'
        }
        $result = Invoke-IntuneWin32AppTest @intuneWin32AppTestSplat
        $result.Status | Should-Be 'Not detected after install'
        $result.Warnings -join ' ' | Should-BeLikeString '*0x87D1041C*'
    }

    It 'reports Install failed for an unmapped exit code and Retry for 1618' {
        $failed = New-Win32Fixture 'd' 'exit 7' 'exit 1'
        $intuneWin32AppTestSplat = @{
            DetectionPath  = $failed.Detection
            ContentPath    = $failed.Content
            InstallCommand = $script:Install
            Architecture   = 'x86'
        }
        (Invoke-IntuneWin32AppTest @intuneWin32AppTestSplat).Status | Should-Be 'Install failed (exit 7)'
        $retry = New-Win32Fixture 'e' 'exit 1618' 'exit 1'
        $intuneWin32AppTestSplat2 = @{
            DetectionPath  = $retry.Detection
            ContentPath    = $retry.Content
            InstallCommand = $script:Install
            Architecture   = 'x86'
        }
        (Invoke-IntuneWin32AppTest @intuneWin32AppTestSplat2).Status | Should-Be 'Retry'
    }

    It 'treats 3010 as success with a pending soft reboot' {
        $fixture = New-Win32Fixture 'f' 'exit 3010' 'exit 1'
        $detectBody = "if (Test-Path '$($fixture.Marker)') { 'installed'; exit 0 } else { exit 1 }"
        $win32FixtureScriptSplat = @{
            Fixture     = $fixture
            DetectBody  = $detectBody
            InstallBody = "Set-Content -Path '$($fixture.Marker)' -Value 1; exit 3010"
        }
        Set-Win32FixtureScript @win32FixtureScriptSplat
        $intuneWin32AppTestSplat = @{
            DetectionPath  = $fixture.Detection
            ContentPath    = $fixture.Content
            InstallCommand = $script:Install
            Architecture   = 'x86'
        }
        $result = Invoke-IntuneWin32AppTest @intuneWin32AppTestSplat
        $result.Status | Should-Be 'Installed after install'
        $result.Warnings -join ' ' | Should-BeLikeString '*softReboot*'
    }
}
