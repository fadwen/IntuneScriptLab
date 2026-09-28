#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The validation driver's helpers, tested without a tenant or a Proxmox host. The driver carries
    #Requires lines for PowerShell 7.6 and Microsoft.Graph.Authentication and runs an action when
    dot-sourced, so its functions are lifted out through the AST into a file under TestDrive and
    dot-sourced from there; Probe.ps1 is copied beside it because ConvertTo-ScriptContent reads it
    from $PSScriptRoot. ssh and Invoke-MgGraphRequest are stubbed, then mocked.
#>

BeforeAll {
    $script:KitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $driver = Join-Path $script:KitRoot 'Invoke-ValidationRound.ps1'

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($driver, [ref]$tokens, [ref]$errors)
    if ($errors) { throw "Invoke-ValidationRound.ps1 does not parse: $($errors[0].Message)" }
    $functions = $ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
    $script:Lifted = Join-Path $TestDrive 'driver-functions.ps1'
    [IO.File]::WriteAllText($script:Lifted, (($functions | ForEach-Object { $_.Extent.Text }) -join "`n`n"))
    Copy-Item (Join-Path $script:KitRoot 'Probe.ps1') (Join-Path $TestDrive 'Probe.ps1')

    # The driver's param block, as the lifted helpers read it through dynamic scoping
    $script:ProxmoxHost = 'pve'
    $script:VmId = 125
    $script:prefix = 'ISL-'

    # Stubs so the commands exist to be mocked; neither is installed on a CI runner. ssh takes its
    # arguments through $args, as a native command would: a declared parameter would make -o ambiguous
    function ssh { throw 'ssh stub called' }
    function Invoke-MgGraphRequest { param($Method, $Uri, $Body) throw "Graph stub called: $Method $Uri $Body" }

    . $script:Lifted

    # Mock bodies see only their own parameters, so call records go through a file under TestDrive
    $script:CallLog = Join-Path $TestDrive 'calls.log'
    function Get-CallLog { if (Test-Path $script:CallLog) { @(Get-Content $script:CallLog) } else { @() } }
}

# The driver targets PowerShell 7.6 (Convert.ToHexString, SHA256.HashData); under Windows PowerShell
# 5.1 the suite reports as skipped rather than failing on the language gap
Describe 'Invoke-ValidationRound helpers' -Tag 'Unit', 'Validation' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {

    BeforeEach {
        Remove-Item $script:CallLog -ErrorAction SilentlyContinue
        Mock Start-Sleep { }
    }

    Context 'Get-AllGraphItem' {
        It 'follows @odata.nextLink until the last page and returns every item' {
            Mock Invoke-MgGraphRequest {
                if ($Uri -like '*skiptoken*') { @{ value = @(@{ id = 'c' }) } }
                else { @{ value = @(@{ id = 'a' }, @{ id = 'b' }); '@odata.nextLink' = "$Uri&`$skiptoken=1" } }
            }
            $items = @(Get-AllGraphItem -Uri '/beta/things')
            $items.id | Should-BeCollection @('a', 'b', 'c')
            Should-Invoke Invoke-MgGraphRequest -Exactly -Times 2
        }

        It 'returns nothing for an empty page instead of failing' {
            Mock Invoke-MgGraphRequest { @{ value = @() } }
            @(Get-AllGraphItem -Uri '/beta/things').Count | Should-Be 0
        }
    }

    Context 'ConvertTo-ScriptContent' {
        It 'prepends Probe.ps1, ends with CRLF and encodes UTF-8 without a BOM by default' {
            $content = ConvertTo-ScriptContent -Body 'exit 0'
            $bytes = [Convert]::FromBase64String($content.Base64)
            $bytes[0] | Should-Be 0x23   # '#', not a BOM
            $text = [Text.Encoding]::UTF8.GetString($bytes)
            $text | Should-BeLikeString "*function Write-ProbeRecord*`r`nexit 0`r`n"
            $content.Sha256 | Should-Be ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)))
        }

        It 'adds the UTF-8 BOM when asked' {
            $bytes = [Convert]::FromBase64String((ConvertTo-ScriptContent -Body 'exit 0' -Bom $true).Base64)
            [Convert]::ToHexString($bytes[0..2]) | Should-Be 'EFBBBF'
        }

        It 'keeps a non-ASCII literal intact' {
            $body = 'Write-Output "Gr' + [char]0xFC + [char]0xDF + 'e"'
            $bytes = [Convert]::FromBase64String((ConvertTo-ScriptContent -Body $body).Base64)
            [Text.Encoding]::UTF8.GetString($bytes) | Should-BeLikeString "*$body*"
        }
    }

    Context 'Invoke-GuestPowerShell' {
        It 'runs the script through qm guest exec as an encoded command and returns stdout' {
            Mock ssh {
                Add-Content -Path (Join-Path $TestDrive 'calls.log') -Value ($args -join ' ')
                $global:LASTEXITCODE = 0
                '{"exitcode":0,"exited":1,"out-data":"hello\n"}'
            }
            $result = Invoke-GuestPowerShell -Script 'Write-Output hello' -TimeoutSeconds 30
            $result | Should-Be "hello`n"
            $call = @(Get-CallLog)[0]
            $call | Should-BeLikeString '-o BatchMode=yes pve qm guest exec 125 --timeout 30 -- powershell*'
            $call | Should-BeLikeString '* -NoProfile -NonInteractive -EncodedCommand *'
            $encoded = ($call -split ' ')[-1]
            $decoded = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded))
            $decoded | Should-Be 'Write-Output hello'
        }

        It 'retries a QMP status timeout and succeeds on a later attempt' {
            Mock ssh {
                Add-Content -Path (Join-Path $TestDrive 'calls.log') -Value 'call'
                if (@(Get-Content (Join-Path $TestDrive 'calls.log')).Count -lt 3) {
                    $global:LASTEXITCODE = 255
                    "VM 125 qmp command 'guest-exec-status' failed - got timeout"
                }
                else {
                    $global:LASTEXITCODE = 0
                    '{"exitcode":0,"exited":1,"out-data":"third"}'
                }
            }
            Invoke-GuestPowerShell -Script 'x' -WarningAction SilentlyContinue | Should-Be 'third'
            @(Get-CallLog).Count | Should-Be 3
            Should-Invoke Start-Sleep -Exactly -Times 2
        }

        It 'gives up after three attempts with the host output in the error' {
            Mock ssh { $global:LASTEXITCODE = 255; 'connection refused' }
            { Invoke-GuestPowerShell -Script 'x' -WarningAction SilentlyContinue } |
                Should-Throw -ExceptionMessage '*qm guest exec failed on pve: connection refused*'
            Should-Invoke ssh -Exactly -Times 3
        }

        It 'warns, but still returns stdout, when the guest script exits non-zero' {
            Mock ssh {
                $global:LASTEXITCODE = 0
                '{"exitcode":1,"exited":1,"out-data":"partial","err-data":"boom"}'
            }
            $warnings = @()
            $result = Invoke-GuestPowerShell -Script 'x' -WarningVariable warnings 3>$null
            $result | Should-Be 'partial'
            "$(@($warnings)[0])" | Should-BeLikeString '*exited 1*boom*'
        }
    }

    Context 'Invoke-GuestScriptFile' {
        BeforeEach {
            # Every guest call is logged with its script; the run call's stdout is what comes back
            Mock Invoke-GuestPowerShell {
                Add-Content -Path (Join-Path $TestDrive 'calls.log') -Value $Script
                if ($Script -like '*WriteAllBytes*') { 'ran' }
            }
        }

        It 'clears old parts, delivers the script as numbered 1,200-character part files and runs it by path' {
            $body = 'Write-Output ' + ('x' * 2000)
            $result = Invoke-GuestScriptFile -Script $body -TimeoutSeconds 60
            $result | Should-Be 'ran'

            $calls = @(Get-CallLog)
            $calls[0] | Should-BeLikeString "Remove-Item -Path 'C:\ProgramData\IntuneScriptLab\collect.ps1.b64*'*"
            $chunks = @($calls | Where-Object { $_ -like 'Set-Content*' })
            $chunks.Count | Should-BeGreaterThan 1
            $chunkShape = "Set-Content -Path 'C:\ProgramData\IntuneScriptLab\collect.ps1.b64.00??' " +
                "-Value '*' -NoNewline"
            foreach ($chunk in $chunks) {
                $chunk | Should-BeLikeString $chunkShape
                ([regex]::Match($chunk, "-Value '([^']*)'").Groups[1].Value.Length) | Should-BeLessThanOrEqual 1200
            }
            $encoded = -join ($chunks | ForEach-Object { [regex]::Match($_, "-Value '([^']*)'").Groups[1].Value })
            $bytes = [Convert]::FromBase64String($encoded)
            [Convert]::ToHexString($bytes[0..2]) | Should-Be 'EFBBBF'
            [Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3) | Should-Be $body

            $calls[-1] | Should-BeLikeString ("*Get-ChildItem -Path " +
                "'C:\ProgramData\IntuneScriptLab\collect.ps1.b64.*'*")
            $calls[-1] | Should-BeLikeString "*WriteAllBytes('C:\ProgramData\IntuneScriptLab\collect.ps1'*"
            $calls[-1] | Should-BeLikeString ('*Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass ' +
                "-Force; & 'C:\ProgramData\IntuneScriptLab\collect.ps1'")
        }

        It 'names the remote file after -RemoteName' {
            $null = Invoke-GuestScriptFile -Script 'x' -RemoteName 'fixtures.ps1'
            (Get-CallLog)[-1] | Should-BeLikeString "*& 'C:\ProgramData\IntuneScriptLab\fixtures.ps1'"
        }

        It 'passes the run timeout only to the run call' {
            Mock Invoke-GuestPowerShell {
                Add-Content -Path (Join-Path $TestDrive 'calls.log') -Value "$TimeoutSeconds|$Script"
            }
            $null = Invoke-GuestScriptFile -Script 'x' -TimeoutSeconds 777
            $calls = @(Get-CallLog)
            $calls[-1] | Should-BeLikeString '777|*'
            @($calls | Where-Object { $_ -like '777|*' }).Count | Should-Be 1
        }
    }
}
