#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The runtime harness against real Windows PowerShell 5.1 processes. Each test encodes a launch
    behaviour observed on the test devices (Validation\Findings.md): the host, the flags, the
    working directory, the copy of the script, the output rules, the timeout and the OEM code
    page. The status logic is unit-tested with the launch mocked under Tests\Unit\Public.
#>

# Real processes, timeouts measured in wall-clock seconds: keep off the parallel path
#pester:no-parallel

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')

    # The 64-bit host that exists on this device
    $osArchitecture = "$([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)"
    $script:Native = if ($osArchitecture -eq 'Arm64') { 'arm64' } else { 'x64' }
    $script:Missing = if ($script:Native -eq 'arm64') { 'x64' } else { 'arm64' }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Runtime harness launch' -Tag 'Integration', 'Runtime' {

    It 'runs Windows PowerShell 5.1 with the agent flags, from system32, from a copy of the script' {
        $path = New-TestScript 'script.ps1' ('"$($PSVersionTable.PSVersion.Major)|' +
            '$([Environment]::GetCommandLineArgs() -join '' '')|$((Get-Location).Path)|$PSScriptRoot"') -Bom
        $result = Invoke-IntunePlatformScriptTest -Path $path -Architecture $script:Native
        $major, $arguments, $cwd, $root = $result.StdOut.Trim() -split '\|'
        $major | Should-Be '5'
        $arguments | Should-BeLikeString '*-NoProfile -ExecutionPolicy Bypass -File*'
        $arguments | Should-NotBeLikeString '*NonInteractive*'
        $cwd | Should-BeLikeString '*\system32'
        $root | Should-NotBe $TestDrive
    }

    It 'switches between the 32-bit and native hosts' {
        $path = New-TestScript 'arch.ps1' '"$([Environment]::Is64BitProcess)|$env:PROCESSOR_ARCHITECTURE"' -Bom
        (Invoke-IntunePlatformScriptTest -Path $path -Architecture x86).StdOut.Trim() |
            Should-BeLikeString 'False|x86'
        (Invoke-IntunePlatformScriptTest -Path $path -Architecture $script:Native).StdOut.Trim() |
            Should-BeLikeString 'True|*'
    }

    It 'refuses the 64-bit host that does not exist on this CPU' {
        $path = New-TestScript 'noop.ps1' 'exit 0' -Bom
        { Invoke-IntunePlatformScriptTest -Path $path -Architecture $script:Missing } | Should-Throw
    }

    It 'kills a script at the timeout and reports TimedOut' {
        $path = New-TestScript 'slow.ps1' 'Start-Sleep -Seconds 30' -Bom
        $result = Invoke-IntunePlatformScriptTest -Path $path -Architecture x86 -TimeoutSeconds 2
        $result.RunState | Should-Be 'TimedOut'
        $result.TimedOut | Should-BeTrue
        $result.Duration.TotalSeconds | Should-BeLessThan 20
    }

    It 'returns immediately from a prompt instead of hanging (documented deviation)' {
        $path = New-TestScript 'prompt.ps1' '$x = Read-Host "name"; "got [$x]"; exit 0' -Bom
        $result = Invoke-IntunePlatformScriptTest -Path $path -Architecture x86 -TimeoutSeconds 30
        $result.TimedOut | Should-BeFalse
    }

    It 'reports the whole platform script output including Write-Host, and Failed on non-zero exit' {
        $intunePlatformScriptTestSplat = @{
            Architecture = 'x86'
            Path         = (New-TestScript 'p1.ps1' "'out-1'; Write-Host 'host-2'; 'out-3'; exit 0" -Bom)
        }
        $ok = Invoke-IntunePlatformScriptTest @intunePlatformScriptTestSplat
        $ok.RunState | Should-Be 'Success'
        $ok.ResultMessage | Should-BeLikeString '*out-1*host-2*out-3*'
        $intunePlatformScriptTestSplat2 = @{
            Architecture = 'x86'
            Path         = (New-TestScript 'p2.ps1' 'Write-Error "deliberate"; exit 1' -Bom)
        }
        $bad = Invoke-IntunePlatformScriptTest @intunePlatformScriptTestSplat2
        $bad.RunState | Should-Be 'Failed'
        $bad.ResultMessage | Should-BeLikeString '*deliberate*'
    }
}

Describe 'Remediation output as Intune reports it' -Tag 'Integration', 'Runtime' {

    It 'treats a script-scope return as exit 0, as Intune does' {
        $detect = New-TestScript 'Detect.ps1' 'Write-Output "found 1"; return 1; exit 1' -Bom
        $result = Invoke-IntuneRemediationTest -DetectionPath $detect -Architecture x86
        $result.Status | Should-Be 'Without issues'
        $result.IntuneOutput | Should-Be '1'
    }

    It 'keeps only the last stdout line and the last 2,048 characters, and warns' {
        $detect = New-TestScript 'Detect.ps1' ("'out-1'; Write-Host 'host-2'; 'out-3'; " +
            "Write-Output ('x' * 3000); exit 0") -Bom
        $result = Invoke-IntuneRemediationTest -DetectionPath $detect -Architecture x86
        $result.IntuneOutput.Length | Should-Be 2048
        $result.IntuneOutput | Should-BeLikeString 'xxxx*'
        $result.Warnings -join ' ' | Should-BeLikeString '*only the last one*'
        $result.Warnings -join ' ' | Should-BeLikeString '*2,048*'
    }

    It 'reports a trailing Write-Warning as the line, prefixed, exactly as Intune did' {
        # Tenant result for REM-OUT-WARNLAST: "WARNING: warn-last"; REM-OUT-HOSTLAST: "host-last"
        $warn = New-TestScript 'Detect.ps1' "Write-Output 'out-first'; Write-Warning 'warn-last'; exit 0" -Bom
        (Invoke-IntuneRemediationTest -DetectionPath $warn -Architecture x86).IntuneOutput |
            Should-Be 'WARNING: warn-last'
        $hostLast = New-TestScript 'Detect2.ps1' "Write-Output 'out-first'; Write-Host 'host-last'; exit 0" -Bom
        (Invoke-IntuneRemediationTest -DetectionPath $hostLast -Architecture x86).IntuneOutput |
            Should-Be 'host-last'
    }

    It 'passes non-ASCII output through the OEM code page like Intune' {
        $text = 'Gr' + [char]0xFC + [char]0xDF + 'e ' + [char]0x2014 + ' ' + [char]0x2713
        $detect = New-TestScript 'Detect.ps1' "Write-Output '$text'; exit 0" -Bom
        $result = Invoke-IntuneRemediationTest -DetectionPath $detect -Architecture x86
        $result.IntuneOutput | Should-NotBe $text
        $result.IntuneOutput | Should-BeLikeString 'Gr*e*'
        $result.Warnings -join ' ' | Should-BeLikeString '*OEM code page*'
    }
}

Describe 'Win32 requirement rules' -Tag 'Integration', 'Runtime' {

    It 'is met by a matching output regardless of case, and by Write-Host (W32-REQ-CASE, W32-REQ-HOST)' {
        $upper = New-TestScript 'req-case.ps1' 'Write-Output "OK"' -Bom
        (Invoke-IntuneRequirementTest -Path $upper -OutputType String -Value 'ok' -Architecture x86).Applicable |
            Should-BeTrue
        $hostOnly = New-TestScript 'req-host.ps1' 'Write-Host "ok"' -Bom
        $result = Invoke-IntuneRequirementTest -Path $hostOnly -OutputType String -Value 'ok' -Architecture x86
        $result.Applicable | Should-BeTrue
        # Write-Host ends the line with a bare LF; the agent strips that like Write-Output's CRLF
        $result.Output | Should-Be 'ok'
        $result.StdOut | Should-Be "ok`n"
    }

    It 'compares the whole output and is failed by exit 1 or stderr (W32-REQ-LASTLINE, EXIT1, STDERR)' {
        $two = New-TestScript 'req-two.ps1' 'Write-Output "first"; Write-Output "ok"' -Bom
        (Invoke-IntuneRequirementTest -Path $two -OutputType String -Value 'ok' -Architecture x86).Applicable |
            Should-BeFalse
        $exit = New-TestScript 'req-exit.ps1' 'Write-Output "ok"; exit 1' -Bom
        (Invoke-IntuneRequirementTest -Path $exit -OutputType String -Value 'ok' -Architecture x86).Reason |
            Should-BeLikeString 'Exit code 1:*'
        $stderr = New-TestScript 'req-err.ps1' 'Write-Output "ok"; Write-Error "oops"; exit 0' -Bom
        (Invoke-IntuneRequirementTest -Path $stderr -OutputType String -Value 'ok' -Architecture x86).Reason |
            Should-BeLikeString '*stderr*'
    }

    It 'parses typed outputs: a version rule accepts 2.10.0 over 2.9.0 (W32-REQ-VER, W32-REQ-INT)' {
        $version = New-TestScript 'req-ver.ps1' 'Write-Output "2.10.0"' -Bom
        $intuneRequirementTestSplat = @{
            Path         = $version
            OutputType   = 'Version'
            Operator     = 'GreaterThanOrEqual'
            Value        = '2.9.0'
            Architecture = 'x86'
        }
        (Invoke-IntuneRequirementTest @intuneRequirementTestSplat).Applicable | Should-BeTrue
        $integer = New-TestScript 'req-int.ps1' 'Write-Output 5' -Bom
        $intuneRequirementTestSplat2 = @{
            Path         = $integer
            OutputType   = 'Integer'
            Operator     = 'GreaterThan'
            Value        = '3'
            Architecture = 'x86'
        }
        (Invoke-IntuneRequirementTest @intuneRequirementTestSplat2).Applicable | Should-BeTrue
    }
}

Describe 'Win32 detection verdicts' -Tag 'Integration', 'Runtime' {

    It 'is detected with exit 0 and stdout, including Write-Host' {
        $a = New-TestScript 'a.ps1' 'Write-Output "installed"; exit 0' -Bom
        (Invoke-IntuneDetectionTest -Path $a -Architecture x86).Detected | Should-BeTrue
        $b = New-TestScript 'b.ps1' 'Write-Host "installed"; exit 0' -Bom
        (Invoke-IntuneDetectionTest -Path $b -Architecture x86).Detected | Should-BeTrue
    }

    It 'is not detected with exit 0 and no stdout' {
        $result = Invoke-IntuneDetectionTest -Path (New-TestScript 'c.ps1' 'exit 0' -Bom) -Architecture x86
        $result.Detected | Should-BeFalse
        $result.Reason | Should-BeLikeString '*Nothing on stdout*'
    }

    It 'is not detected when anything reaches stderr, even with stdout and exit 0' {
        $path = New-TestScript 'd.ps1' 'Write-Output "installed"; Write-Error "oops"; exit 0' -Bom
        $result = Invoke-IntuneDetectionTest -Path $path -Architecture x86
        $result.Detected | Should-BeFalse
        $result.Reason | Should-BeLikeString '*stderr*'
    }

    It 'is detected despite Write-Warning, which is not stderr' {
        $path = New-TestScript 'e.ps1' 'Write-Output "installed"; Write-Warning "careful"; exit 0' -Bom
        (Invoke-IntuneDetectionTest -Path $path -Architecture x86).Detected | Should-BeTrue
    }

    It 'is not detected on a non-zero exit or a throw' {
        $f = New-TestScript 'f.ps1' 'Write-Output "installed"; exit 1' -Bom
        (Invoke-IntuneDetectionTest -Path $f -Architecture x86).Detected | Should-BeFalse
        $g = New-TestScript 'g.ps1' 'Write-Output "installed"; throw "boom"' -Bom
        (Invoke-IntuneDetectionTest -Path $g -Architecture x86).Detected | Should-BeFalse
    }
}
