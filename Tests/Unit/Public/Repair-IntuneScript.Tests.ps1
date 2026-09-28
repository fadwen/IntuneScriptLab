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

        It 'expands a folder and reports one object per script' {
            $folder = Join-Path $TestDrive 'Tree'
            New-TestScript 'Tree\Remediations\One\Detect.ps1' "return 'a'`nexit 1" -Bom | Out-Null
            New-TestScript 'Tree\Remediations\Two\Detect.ps1' "Write-Output 'b'`nexit 1" -Bom | Out-Null
            $results = @(Repair-IntuneScript -Path $folder)
            $results.Count | Should-Be 2
            ($results | Where-Object Path -like '*One*').Applied | Should-Be 1
            ($results | Where-Object Path -like '*Two*').Applied | Should-Be 0
        }
    }
}
