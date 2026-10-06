#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The fixer: the script-scope return, the encoding and the padded requirement value, each
    rewritten in place with the file's bytes checked afterwards, plus -WhatIf, the pipeline, and
    a file with nothing to fix.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
    $script:Utf8Bom = [System.Text.UTF8Encoding]::new($true)
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Repair-IntuneScript' -Tag 'Unit', 'Public' {

    Context 'Script-scope return' {
        It 'turns return <value> into the output and exit 0 it already implied, and keeps the line endings' {
            $body = "if (Test-Path C:\x) { return 'ok' }`r`nexit 1`r`n"
            $path = New-TestScript 'Remediations\A\Detect.ps1' $body -Bom
            $result = Repair-IntuneScript -Path $path
            $result.PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.Repair'
            $result.Applied | Should-Be 1
            $result.Written | Should-BeTrue
            $result.Fixes[0].RuleName | Should-Be 'IslExitCodeIssue'
            $result.Fixes[0].Before | Should-Be "return 'ok'"
            $result.Fixes[0].After | Should-Be "'ok'; exit 0"
            $text = [System.IO.File]::ReadAllText($path)
            $text | Should-Be "if (Test-Path C:\x) { 'ok'; exit 0 }`r`nexit 1`r`n"
            @(Test-IntuneScript -Path $path).RuleName | Should-NotContainCollection 'IslExitCodeIssue'
            $result.Remaining | Should-Be @(Test-IntuneScript -Path $path).Count
        }

        It 'turns a bare return in a remediation into exit 0, and applies several edits from the end' {
            $body = "if (`$a) { return }`nif (`$b) { return 'done' }`nexit 0"
            $path = New-TestScript 'Remediations\B\Remediate.ps1' $body -Bom
            $result = Repair-IntuneScript -Path $path
            $result.Applied | Should-Be 2
            [System.IO.File]::ReadAllText($path) |
                Should-Be "if (`$a) { exit 0 }`nif (`$b) { 'done'; exit 0 }`nexit 0"
        }

        It 'leaves a return alone when an exit other than 0 follows it, and the finding with it' {
            # 'return 1; exit 1' made explicit would read '1; exit 0; exit 1': the same behaviour, the
            # exit the author meant unreachable, and nothing left to report it
            $body = "Write-Output 'found'`nreturn 1`nexit 1"
            $path = New-TestScript 'Remediations\E\Detect.ps1' $body -Bom
            $result = Repair-IntuneScript -Path $path
            $result.Applied | Should-Be 0
            $result.Written | Should-BeFalse
            [System.IO.File]::ReadAllText($path) | Should-Be $body
            $left = @(Test-IntuneScript -Path $path | Where-Object RuleName -eq 'IslExitCodeIssue')
            $left.Severity | Should-ContainCollection 'Error'
            $result.Remaining | Should-Be @(Test-IntuneScript -Path $path).Count
        }
    }

    Context 'Encoding' {
        It 'adds a BOM to a UTF-8 file with non-ASCII text and keeps the text intact' {
            $body = 'Write-Output "Gr' + [char]0xFC + [char]0xDF + 'e"; exit 0'
            $path = New-TestScript 'Detect-Umlaut.ps1' $body
            $result = Repair-IntuneScript -Path $path
            $result.Applied | Should-Be 1
            $result.Fixes[0].RuleName | Should-Be 'IslEncodingIssue'
            $result.Fixes[0].After | Should-Be 'utf-8 with BOM'
            $bytes = [System.IO.File]::ReadAllBytes($path)
            @($bytes[0], $bytes[1], $bytes[2]) | Should-BeCollection @(0xEF, 0xBB, 0xBF)
            [System.IO.File]::ReadAllText($path) | Should-Be $body
            @(Test-IntuneScript -Path $path -IncludeRule IslEncodingIssue).Severity |
                Should-NotContainCollection 'Warning'
        }

        It 'converts a UTF-16 file to UTF-8 with a BOM' {
            $body = "Write-Output 'sixteen'; exit 0"
            $path = New-TestScript 'Detect-Wide.ps1' $body -Utf16
            $result = Repair-IntuneScript -Path $path
            $result.Applied | Should-Be 1
            $result.Fixes[0].Before | Should-Be 'utf-16'
            $bytes = [System.IO.File]::ReadAllBytes($path)
            @($bytes[0], $bytes[1], $bytes[2]) | Should-BeCollection @(0xEF, 0xBB, 0xBF)
            [System.IO.File]::ReadAllText($path) | Should-Be $body
        }
    }

    Context 'Padded requirement value' {
        It 'trims the literal and keeps its quotes' {
            $path = New-TestScript 'Win32\App\Requirement.ps1' "Write-Output ' ok '`nexit 0" -Bom
            $result = Repair-IntuneScript -Path $path
            $result.Applied | Should-Be 1
            $result.Fixes[0].Before | Should-Be "' ok '"
            $result.Fixes[0].After | Should-Be "'ok'"
            [System.IO.File]::ReadAllText($path) | Should-Be "Write-Output 'ok'`nexit 0"
        }
    }

    Context 'Mechanical fixes' {
        It 'applies the <Rule> fix: <Before> becomes <After>' -ForEach @(
            @{ Rule = 'IslInteractiveCall'; Type = 'Remediation'; Name = 'Remediate.ps1'
                Before = 'Install-Module Foo'; After = 'Install-Module Foo -Force' }
            @{ Rule = 'IslInteractiveCall'; Type = 'Remediation'; Name = 'Remediate.ps1'
                Before = "Register-PSRepository -Name r -SourceLocation 'https://x'"
                After = "Register-PSRepository -Name r -SourceLocation 'https://x' -Confirm:`$false" }
            @{ Rule = 'IslInteractiveCall'; Type = 'Remediation'; Name = 'Remediate.ps1'
                Before = "`$c = Import-Clixml C:\c.xml`n`$cred = Get-Credential -Credential `$c"
                After = "`$c = Import-Clixml C:\c.xml`n`$cred = `$c" }
            @{ Rule = 'IslExecutionPolicyCall'; Type = 'Remediation'; Name = 'Remediate.ps1'
                Before = "Set-ExecutionPolicy Bypass -Scope Process -Force`nWrite-Output 'x'"
                After = "`nWrite-Output 'x'" }
            @{ Rule = 'IslArchitectureIssue'; Type = 'Remediation'; Name = 'Detect.ps1'
                Before = 'Test-Path "$env:ProgramFiles\Widget\w.exe"'
                After = 'Test-Path "$env:ProgramW6432\Widget\w.exe"' }
            @{ Rule = 'IslArm64Assumption'; Type = 'Remediation'; Name = 'Detect.ps1'; Architecture = 'arm64'
                Before = "if (`$env:PROCESSOR_ARCHITECTURE -match 'AMD64') { 'x64' }"
                After = "if (`$env:PROCESSOR_ARCHITECTURE -match 'ARM64|AMD64') { 'x64' }" }
            @{ Rule = 'IslOutputIssue'; Type = 'Win32Detection'; Name = 'Detect-App.ps1'
                Before = 'Get-Item C:\Widget\w.exe'
                After = 'Get-Item C:\Widget\w.exe -ErrorAction SilentlyContinue' }
            @{ Rule = 'IslExitCodeIssue'; Type = 'Detection'; Name = 'Detect.ps1'
                Before = "if (Test-Path C:\x) { exit 2 }`nexit 0"
                After = "if (Test-Path C:\x) { exit 1 }`nexit 0" }
            @{ Rule = 'IslRelativePath'; Type = 'Remediation'; Name = 'Remediate.ps1'
                Before = 'Get-Content (Join-Path $PWD settings.json)'
                After = 'Get-Content (Join-Path $PSScriptRoot settings.json)' }
            @{ Rule = 'IslPowerShell7Syntax'; Type = 'Remediation'; Name = 'Remediate.ps1'
                Before = "#Requires -Version 7.0`nWrite-Output 'x'"; After = "`nWrite-Output 'x'" }
        ) {
            # Each is the edit the finding's own message asks for, so the finding and its fix agree
            $folder = if ($Type -eq 'Win32Detection') { 'Win32\M' } else { 'Remediations\M' }
            $path = New-TestScript "$folder\$Name" $Before -Bom
            $repairSplat = @{ Path = $path; ScriptType = $Type; IncludeRule = $Rule }
            if ($Architecture) { $repairSplat.Architecture = $Architecture }
            $result = Repair-IntuneScript @repairSplat
            $result.Applied | Should-Be 1
            $result.Fixes[0].RuleName | Should-Be $Rule
            [System.IO.File]::ReadAllText($path) | Should-Be $After
            $testSplat = @{ Path = $path; ScriptType = $Type; IncludeRule = $Rule }
            if ($Architecture) { $testSplat.Architecture = $Architecture }
            @(Test-IntuneScript @testSplat | Where-Object { $_.Fix }).Count | Should-Be 0
        }

        It 'withholds a fix that would break the script: <Case>' -ForEach @(
            @{ Case = 'Set-ExecutionPolicy inside a pipeline'; Rule = 'IslExecutionPolicyCall'
                Body = 'Set-ExecutionPolicy Bypass -Scope Process -Force | Out-Null' }
            @{ Case = "'AMD64' compared with -eq"; Rule = 'IslArm64Assumption'; Architecture = 'arm64'
                Body = "if (`$env:PROCESSOR_ARCHITECTURE -eq 'AMD64') { 'x64' }" }
            @{ Case = '$PWD with a member after it'; Rule = 'IslRelativePath'
                Body = 'Get-Content "$($PWD.Path)\s.json"' }
            @{ Case = 'Set-ExecutionPolicy without -Force, which another rule removes'; Rule = 'IslInteractiveCall'
                Body = 'Set-ExecutionPolicy RemoteSigned' }
        ) {
            $path = New-TestScript 'Remediations\N\Remediate.ps1' $Body -Bom
            $testSplat = @{ Path = $path; ScriptType = 'Remediation'; IncludeRule = $Rule }
            if ($Architecture) { $testSplat.Architecture = $Architecture }
            $findings = @(Test-IntuneScript @testSplat)
            $findings.Count | Should-BeGreaterThan 0
            @($findings | Where-Object { $_.Fix }).Count | Should-Be 0
            $result = Repair-IntuneScript @testSplat
            $result.Applied | Should-Be 0
            [System.IO.File]::ReadAllText($path) | Should-Be $Body
        }
    }

    Context 'Behaviour' {
        It 'changes nothing under -WhatIf but still reports what it would do' {
            $body = "if (Test-Path C:\x) { return 'ok' }`nexit 1"
            $path = New-TestScript 'Remediations\C\Detect.ps1' $body -Bom
            $result = Repair-IntuneScript -Path $path -WhatIf
            $result.Applied | Should-Be 1
            $result.Written | Should-BeFalse
            [System.IO.File]::ReadAllText($path) | Should-Be $body
        }

        It 'leaves a script with nothing to fix alone and counts its findings as remaining' {
            $path = New-TestScript 'Detect-Fine.ps1' "Write-Host 'x'`nStart-Sleep -Seconds 4000`nexit 1" -Bom
            $stamp = (Get-Item $path).LastWriteTimeUtc
            $result = Repair-IntuneScript -Path $path
            $result.Applied | Should-Be 0
            $result.Written | Should-BeFalse
            $result.Remaining | Should-Be @(Test-IntuneScript -Path $path).Count
            (Get-Item $path).LastWriteTimeUtc | Should-Be $stamp
        }

        It 'honours the rule filters and takes files from the pipeline' {
            $body = "if (Test-Path C:\x) { return 'ok' }`nexit 1"
            $path = New-TestScript 'Remediations\D\Detect.ps1' $body -Bom
            $skipped = Get-ChildItem $path | Repair-IntuneScript -ExcludeRule IslExitCodeIssue
            $skipped.Applied | Should-Be 0
            [System.IO.File]::ReadAllText($path) | Should-Be $body
            $fixed = Get-ChildItem $path | Repair-IntuneScript -IncludeRule IslExitCodeIssue
            $fixed.Applied | Should-Be 1
        }

        It 'hands -Context and -EnforceSignatureCheck to the analysis, on both runs' {
            # Without them the repair analyzed every script under the inferred context whatever the
            # caller deployed to, so Remaining could disagree with Test-IntuneScript run with the
            # same options. HKCU: and USERPROFILE are two errors under System (REM-PROBE-SYS64) and
            # under User the rule gives one note; an unsigned Win32 detection is an error only with
            # the signature check enforced
            $body = "Get-ItemProperty HKCU:\Software\Contoso`nTest-Path `$env:USERPROFILE\x`nexit 1"
            $path = New-TestScript 'Remediations\F\Detect.ps1' $body -Bom
            $asUser = Repair-IntuneScript -Path $path -Context User -IncludeRule IslContextIssue
            $asSystem = Repair-IntuneScript -Path $path -Context System -IncludeRule IslContextIssue
            $asUser.Remaining | Should-Be 1
            $asSystem.Remaining | Should-Be 2

            $unsigned = New-TestScript 'Win32\F\Detect-App.ps1' "if (Test-Path C:\x) { exit 0 }`nexit 1" -Bom
            $enforced = Repair-IntuneScript -Path $unsigned -ScriptType Win32Detection -EnforceSignatureCheck
            $plain = Repair-IntuneScript -Path $unsigned -ScriptType Win32Detection
            $enforced.Remaining | Should-Be ($plain.Remaining + 1)
        }

        It 'counts the architecture the caller names, not the inferred one, in Remaining' {
            # x86 is the portal default for a remediation, so the 32-bit System32 finding is there
            # under Auto and gone under -Architecture x64 (REM-PROBE-SYS32)
            $body = "Start-Process C:\Windows\System32\msiexec.exe -Wait`nexit 0"
            $folder = New-TestScript 'Remediations\G\Detect.ps1' $body -Bom
            $inferred = Repair-IntuneScript -Path $folder
            $native = Repair-IntuneScript -Path $folder -Architecture x64
            $inferred.Remaining | Should-Be (@(Test-IntuneScript -Path $folder).Count)
            $native.Remaining | Should-Be (@(Test-IntuneScript -Path $folder -Architecture x64).Count)
            $native.Remaining | Should-BeLessThan $inferred.Remaining
        }

        It 'expands a folder and reports one object per script' {
            $folder = Join-Path $TestDrive 'Tree'
            New-TestScript 'Tree\Remediations\One\Detect.ps1' "if (`$a) { return 'a' }`nexit 1" -Bom | Out-Null
            New-TestScript 'Tree\Remediations\Two\Detect.ps1' "Write-Output 'b'`nexit 1" -Bom | Out-Null
            $results = @(Repair-IntuneScript -Path $folder)
            $results.Count | Should-Be 2
            ($results | Where-Object Path -like '*One*').Applied | Should-Be 1
            ($results | Where-Object Path -like '*Two*').Applied | Should-Be 0
        }

        It 'lists what it would do for a folder under -WhatIf' {
            $folder = Join-Path $TestDrive 'WhatIfTree'
            $body = "if (`$a) { return 'a' }`nexit 1"
            $path = New-TestScript 'WhatIfTree\Remediations\One\Detect.ps1' $body -Bom
            $results = @(Repair-IntuneScript -Path $folder -WhatIf)
            $results.Count | Should-Be 1
            $results[0].Applied | Should-Be 1
            $results[0].Written | Should-BeFalse
            [System.IO.File]::ReadAllText($path) | Should-Be $body
        }

        It 'reads a BOM-less file that is not UTF-8 as ANSI and writes it back as UTF-8 with a BOM, intact' {
            $path = Join-Path $TestDrive 'Detect-Ansi.ps1'
            $text = 'Write-Output "Gr' + [char]0xFC + [char]0xDF + 'e"' + "`nexit 0"
            [System.IO.File]::WriteAllBytes($path, [System.Text.Encoding]::GetEncoding(1252).GetBytes($text))
            $result = Repair-IntuneScript -Path $path -ScriptType PlatformScript
            $result.Written | Should-BeTrue
            $bytes = [System.IO.File]::ReadAllBytes($path)
            @($bytes[0], $bytes[1], $bytes[2]) | Should-BeCollection @([byte]0xEF, [byte]0xBB, [byte]0xBF)
            [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3) | Should-Be $text
        }
    }
}
