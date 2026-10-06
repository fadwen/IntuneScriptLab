#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The validation driver's helpers, tested without a tenant or a Proxmox host. The driver carries
    #Requires lines for PowerShell 7.6 and Microsoft.Graph.Authentication and runs an action when
    dot-sourced, so its functions are lifted out through the AST into a file under TestDrive and
    dot-sourced from there; Probe.ps1 is copied beside it because ConvertTo-ScriptContent reads it
    from $PSScriptRoot. GuestAgent.ps1, the guest agent transport both kit scripts dot-source, is
    dot-sourced as it is. ssh and Invoke-MgGraphRequest are stubbed, then mocked.
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
    . (Join-Path $script:KitRoot 'GuestAgent.ps1')

    # Mock bodies see only their own parameters, so call records go through a file under TestDrive
    $script:CallLog = Join-Path $TestDrive 'calls.log'
    function Get-CallLog { if (Test-Path $script:CallLog) { @(Get-Content $script:CallLog) } else { @() } }

    # What the fake Proxmox host answers, one line per call and the last line repeated: the start
    # calls ("qm guest exec") and the result calls ("qm guest exec-status") each have a queue.
    # "{M}" stands for the marker the command under test printed first; "!255 text" is a failed call
    function Use-HostReply {
        param([string[]]$Start = '{"pid":4242}', [Parameter(Mandatory)][string[]]$Status)
        Set-Content -Path (Join-Path $TestDrive 'start-replies.txt') -Value $Start
        Set-Content -Path (Join-Path $TestDrive 'status-replies.txt') -Value $Status
    }
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
        BeforeEach {
            # The fake host: logs every call, remembers the marker of the command it was asked to
            # start, and answers from the queues Use-HostReply wrote
            Mock ssh {
                $line = $args -join ' '
                Add-Content -Path (Join-Path $TestDrive 'calls.log') -Value $line
                $kind = if ($line -like '*guest exec-status*') { 'status' } else { 'start' }
                if ($kind -eq 'start') {
                    $encoded = ($line -split ' ')[-1]
                    $decoded = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded))
                    $marker = ($decoded -split "`n")[0].Trim("'")
                    Set-Content -Path (Join-Path $TestDrive 'marker.txt') -Value $marker
                    Set-Content -Path (Join-Path $TestDrive 'sent.txt') -Value $decoded -NoNewline
                }
                $queue = Join-Path $TestDrive "$kind-replies.txt"
                $replies = @(Get-Content -Path $queue)
                $reply = $replies[0]
                if ($replies.Count -gt 1) { Set-Content -Path $queue -Value $replies[1..($replies.Count - 1)] }
                $global:LASTEXITCODE = 0
                if ($reply -match '^!(\d+) (.*)$') {
                    $global:LASTEXITCODE = [int]$Matches[1]
                    $reply = $Matches[2]
                }
                $reply.Replace('{M}', (Get-Content -Path (Join-Path $TestDrive 'marker.txt') -Raw).Trim())
            }
        }

        It 'starts the command without waiting, asks for its result by process id and returns stdout' {
            Use-HostReply -Status '{"exitcode":0,"exited":1,"out-data":"{M}\r\nhello\n"}'
            $result = Invoke-GuestPowerShell -Script 'Write-Output hello' -TimeoutSeconds 30
            $result | Should-Be "hello`n"

            $calls = @(Get-CallLog)
            $calls.Count | Should-Be 2
            $calls[0] | Should-BeLikeString '-o BatchMode=yes pve qm guest exec 125 --synchronous 0 -- powershell*'
            $calls[0] | Should-BeLikeString '* -NoProfile -NonInteractive -EncodedCommand *'
            $calls[1] | Should-Be '-o BatchMode=yes pve qm guest exec-status 125 4242'
            # The command prints a marker of its own before anything else
            $marker = (Get-Content (Join-Path $TestDrive 'marker.txt') -Raw).Trim()
            $marker | Should-MatchString '^[0-9a-f]{32}$'
            Get-Content (Join-Path $TestDrive 'sent.txt') -Raw | Should-Be "'$marker'`nWrite-Output hello"
        }

        It 'uses a different marker for every command' {
            Use-HostReply -Status '{"exitcode":0,"exited":1,"out-data":"{M}\r\n"}'
            $null = Invoke-GuestPowerShell -Script 'x'
            $first = (Get-Content (Join-Path $TestDrive 'marker.txt') -Raw).Trim()
            $null = Invoke-GuestPowerShell -Script 'x'
            (Get-Content (Join-Path $TestDrive 'marker.txt') -Raw).Trim() | Should-NotBe $first
        }

        It 'asks again while the command is still running' {
            $running = '{"exited":0}'
            Use-HostReply -Status $running, $running, '{"exitcode":0,"exited":1,"out-data":"{M}\r\ndone"}'
            Invoke-GuestPowerShell -Script 'x' | Should-Be 'done'
            @(Get-CallLog | Where-Object { $_ -like '*exec-status*' }).Count | Should-Be 3
        }

        It 'keeps asking after a status call times out while the agent still holds the result' {
            # The call timed out with the command still running: nothing was handed over, so the
            # result is still there to collect and the command is not started a second time
            $timeout = "!255 VM 125 qmp command 'guest-exec-status' failed - got timeout"
            Use-HostReply -Status $timeout, $timeout, '{"exitcode":0,"exited":1,"out-data":"{M}\r\nthird"}'
            Invoke-GuestPowerShell -Script 'x' | Should-Be 'third'
            @(Get-CallLog | Where-Object { $_ -like '*guest exec 125 --synchronous*' }).Count | Should-Be 1
            @(Get-CallLog | Where-Object { $_ -like '*exec-status*' }).Count | Should-Be 3
        }

        It 'runs the command again when a status call that timed out took the result with it (VM 125)' {
            # Traced on the device: "got timeout", then "PID does not exist". The agent had answered
            # the call that the host gave up on, and a result is handed over once
            $timeout = "!255 VM 125 qmp command 'guest-exec-status' failed - got timeout"
            $gone = '!29 Agent error: PID lld does not exist'
            Use-HostReply -Status $timeout, $gone, '{"exitcode":0,"exited":1,"out-data":"{M}\r\nsecond run"}'
            $warnings = @()
            Invoke-GuestPowerShell -Script 'x' -WarningVariable warnings 3>$null | Should-Be 'second run'
            @(Get-CallLog | Where-Object { $_ -like '*guest exec 125 --synchronous*' }).Count | Should-Be 2
            "$(@($warnings)[0])" |
                Should-BeLikeString '*went with a status call that timed out*running the command again'
        }

        It 'does not take another command''s result for its own when its own was lost' {
            $stale = '{"exitcode":0,"exited":1,"out-data":"0123456789abcdef0123456789abcdef\r\nsomeone else"}'
            $timeout = "!255 VM 125 qmp command 'guest-exec-status' failed - got timeout"
            $gone = '!29 Agent error: PID lld does not exist'
            Use-HostReply -Status $stale, $timeout, $gone, '{"exitcode":0,"exited":1,"out-data":"{M}\r\nmine"}'
            Invoke-GuestPowerShell -Script 'x' -WarningAction SilentlyContinue | Should-Be 'mine'
            @(Get-CallLog | Where-Object { $_ -like '*guest exec 125 --synchronous*' }).Count | Should-Be 2
        }

        It 'gives up when the result is lost three times running' {
            $timeout = "!255 VM 125 qmp command 'guest-exec-status' failed - got timeout"
            $gone = '!29 Agent error: PID lld does not exist'
            Use-HostReply -Status $timeout, $gone, $timeout, $gone, $timeout, $gone
            { Invoke-GuestPowerShell -Script 'x' -WarningAction SilentlyContinue } |
                Should-Throw -ExceptionMessage '*result was lost to a timed-out status call 3 times*'
            @(Get-CallLog | Where-Object { $_ -like '*guest exec 125 --synchronous*' }).Count | Should-Be 3
        }

        It 'passes over an earlier command''s result held under the same process id (Collect, 2026-10-05)' {
            # The agent answers with the oldest result it holds for a process id, and Windows reuses
            # ids: a payload chunk came back as another chunk, the right length and the wrong text
            $stale = '{"exitcode":0,"exited":1,"out-data":"0123456789abcdef0123456789abcdef\r\nsomeone else"}'
            Use-HostReply -Status $stale, '{"exitcode":0,"exited":1,"out-data":"{M}\r\nmine"}'
            Invoke-GuestPowerShell -Script 'x' | Should-Be 'mine'
            @(Get-CallLog | Where-Object { $_ -like '*guest exec 125 --synchronous*' }).Count | Should-Be 1
            @(Get-CallLog | Where-Object { $_ -like '*exec-status*' }).Count | Should-Be 2
        }

        It 'takes a reply without the marker as its own when the agent holds nothing else for the id' {
            # powershell.exe that never reached the first line: no marker, and no second result
            $gone = '!29 Agent error: PID lld does not exist'
            Use-HostReply -Status '{"exitcode":1,"exited":1,"err-data":"boom"}', $gone
            $warnings = @()
            $result = Invoke-GuestPowerShell -Script 'x' -WarningVariable warnings 3>$null
            $result | Should-Be ''
            "$(@($warnings)[0])" | Should-BeLikeString '*exited 1*boom*'
        }

        It 'fails when the agent holds no result at all for the process id' {
            Use-HostReply -Status '!29 Agent error: PID lld does not exist'
            { Invoke-GuestPowerShell -Script 'x' } |
                Should-Throw -ExceptionMessage '*holds no result for process id 4242*'
        }

        It 'retries a start call that times out and succeeds on a later attempt' {
            $timeout = "!255 VM 125 qmp command 'guest-exec' failed - got timeout"
            $finished = '{"exitcode":0,"exited":1,"out-data":"{M}\r\nok"}'
            Use-HostReply -Start $timeout, $timeout, '{"pid":4242}' -Status $finished
            Invoke-GuestPowerShell -Script 'x' -WarningAction SilentlyContinue | Should-Be 'ok'
            @(Get-CallLog | Where-Object { $_ -like '*guest exec 125 --synchronous*' }).Count | Should-Be 3
            Should-Invoke Start-Sleep -Exactly -Times 2 -ParameterFilter { $Seconds -eq 10 }
        }

        It 'gives up after three failed starts with the host output in the error' {
            Use-HostReply -Start '!255 connection refused' -Status '{"exited":0}'
            { Invoke-GuestPowerShell -Script 'x' -WarningAction SilentlyContinue } |
                Should-Throw -ExceptionMessage '*qm guest exec failed on pve: connection refused*'
            Should-Invoke ssh -Exactly -Times 3
        }

        It 'gives up when the command has not finished by the timeout' {
            Use-HostReply -Status '{"exited":0}'
            { Invoke-GuestPowerShell -Script 'x' -TimeoutSeconds 0 } |
                Should-Throw -ExceptionMessage '*process id 4242 on VM 125) did not finish within 0 s*'
        }

        It 'gives up when the result calls keep failing' {
            Use-HostReply -Status '!255 connection refused'
            { Invoke-GuestPowerShell -Script 'x' -TimeoutSeconds 600 } |
                Should-Throw -ExceptionMessage '*qm guest exec-status failed on pve: connection refused*'
            @(Get-CallLog | Where-Object { $_ -like '*exec-status*' }).Count | Should-Be 10
        }

        It 'warns, but still returns stdout, when the guest script exits non-zero' {
            Use-HostReply -Status '{"exitcode":1,"exited":1,"out-data":"{M}\r\npartial","err-data":"boom"}'
            $warnings = @()
            $result = Invoke-GuestPowerShell -Script 'x' -WarningVariable warnings 3>$null
            $result | Should-Be 'partial'
            "$(@($warnings)[0])" | Should-BeLikeString '*exited 1*boom*'
        }

        It 'warns about stderr on a zero exit and leaves progress records out' {
            $progress = '#< CLIXML\r\n<Objs Version=\"1.1.0.1\" ' +
                'xmlns=\"http://schemas.microsoft.com/powershell/2004/04\">' +
                '<Obj S=\"progress\" RefId=\"0\"><TN RefId=\"0\">' +
                '<T>System.Management.Automation.PSCustomObject</T>' +
                '<T>System.Object</T></TN><MS><I64 N=\"SourceId\">1</I64></MS></Obj></Objs>'
            $withProgress = '{"exitcode":0,"exited":1,"out-data":"{M}\r\nfine","err-data":"' + $progress + '"}'
            Use-HostReply -Status $withProgress
            $quiet = @()
            Invoke-GuestPowerShell -Script 'x' -WarningVariable quiet 3>$null | Should-Be 'fine'
            @($quiet).Count | Should-Be 0

            Use-HostReply -Status '{"exitcode":0,"exited":1,"out-data":"{M}\r\nfine","err-data":"not good"}'
            $warnings = @()
            $null = Invoke-GuestPowerShell -Script 'x' -WarningVariable warnings 3>$null
            "$(@($warnings)[0])" | Should-Be 'not good'
        }
    }

    Context 'Send-GuestFile' {
        BeforeEach {
            # The fake host accepts every file-write; the fake VM answers the join call with the hash
            # the test put in hash.txt
            Mock ssh {
                Add-Content -Path (Join-Path $TestDrive 'calls.log') -Value ($args -join ' ')
                $global:LASTEXITCODE = 0
            }
            Mock Invoke-GuestPowerShell {
                Add-Content -Path (Join-Path $TestDrive 'calls.log') -Value "guest|$Script"
                if ($Script -like '*Get-FileHash*') {
                    (Get-Content -Path (Join-Path $TestDrive 'hash.txt') -Raw).Trim()
                }
            }
            $script:Bytes = [Text.Encoding]::ASCII.GetBytes('y' * 50000)
            $sha = [Security.Cryptography.SHA256]::Create()
            $script:BytesHash = [BitConverter]::ToString($sha.ComputeHash($script:Bytes)) -replace '-', ''
            $sha.Dispose()
            Set-Content -Path (Join-Path $TestDrive 'hash.txt') -Value $script:BytesHash
        }

        It 'writes the bytes as 30,000-character base64 parts, joins them on the VM and checks the hash' {
            Send-GuestFile -RemotePath 'C:\ProgramData\IntuneScriptLab\thing.bin' -Bytes $script:Bytes
            $calls = @(Get-CallLog)
            $calls[0] | Should-BeLikeString ("guest|`$null = New-Item -ItemType Directory -Path " +
                "'C:\ProgramData\IntuneScriptLab' -Force; " +
                "Remove-Item -Path 'C:\ProgramData\IntuneScriptLab\thing.bin.b64.*'*")
            $writes = @($calls | Where-Object { $_ -like '*file-write*' })
            $writes.Count | Should-Be 3
            $shape = "-o BatchMode=yes pve pvesh create /nodes/`$(hostname)/qemu/125/agent/file-write " +
                "--file 'C:\ProgramData\IntuneScriptLab\thing.bin.b64.000?' --content '*'"
            foreach ($write in $writes) { $write | Should-BeLikeString $shape }
            $parts = $writes | ForEach-Object { [regex]::Match($_, "--content '([^']*)'").Groups[1].Value }
            @($parts | ForEach-Object Length) | Should-BeCollection @(30000, 30000, 6668)
            (-join $parts) | Should-Be ([Convert]::ToBase64String($script:Bytes))
            $join = $calls[-1]
            $join |
                Should-BeLikeString "guest|*Get-ChildItem -Path 'C:\ProgramData\IntuneScriptLab\thing.bin.b64.*'*"
            $join | Should-BeLikeString "*WriteAllBytes('C:\ProgramData\IntuneScriptLab\thing.bin'*"
            $join |
                Should-BeLikeString "*Remove-Item -Path '*\thing.bin.b64.*'*Get-FileHash*"
        }

        It 'refuses a file the VM hashes differently' {
            Set-Content -Path (Join-Path $TestDrive 'hash.txt') -Value ('0' * 64)
            { Send-GuestFile -RemotePath 'C:\x\thing.bin' -Bytes $script:Bytes } |
                Should-Throw -ExceptionMessage ("*thing.bin did not arrive intact: the VM hashes it 000*" +
                    "local bytes hash $($script:BytesHash)")
        }

        It 'fails naming the part when the host refuses a file-write' {
            Mock ssh { $global:LASTEXITCODE = 255; 'no such VM' }
            { Send-GuestFile -RemotePath 'C:\x\thing.bin' -Bytes $script:Bytes } |
                Should-Throw -ExceptionMessage "*file-write of C:\x\thing.bin.b64.0000 failed on pve: no such VM*"
        }
    }

    Context 'Receive-GuestFile' {
        BeforeAll {
            $sha = [Security.Cryptography.SHA256]::Create()
            $digest = $sha.ComputeHash([Text.Encoding]::ASCII.GetBytes('abc'))
            $script:AbcHash = [BitConverter]::ToString($digest) -replace '-', ''
            $sha.Dispose()
        }

        It 'reads the file in one file-read call and returns its text when the hash matches' {
            Mock ssh {
                Add-Content -Path (Join-Path $TestDrive 'calls.log') -Value ($args -join ' ')
                $global:LASTEXITCODE = 0
                '{', '   "bytes-read" : 3,', '   "content" : "abc"', '}'
            }
            Receive-GuestFile -RemotePath 'C:\ProgramData\IntuneScriptLab\collect.b64' -Sha256 $script:AbcHash |
                Should-Be 'abc'
            @(Get-CallLog)[0] | Should-Be ("-o BatchMode=yes pve pvesh get /nodes/`$(hostname)/qemu/125/agent/" +
                "file-read " +
                "--file 'C:\ProgramData\IntuneScriptLab\collect.b64' --output-format json")
        }

        It 'refuses a reply the agent marked truncated' {
            Mock ssh { $global:LASTEXITCODE = 0; '{"bytes-read":3,"content":"abc","truncated":true}' }
            { Receive-GuestFile -RemotePath 'C:\x\big.b64' -Sha256 $script:AbcHash } |
                Should-Throw -ExceptionMessage '*big.b64 is longer than the 16 MB*'
        }

        It 'refuses text whose hash is not the VM''s' {
            Mock ssh { $global:LASTEXITCODE = 0; '{"bytes-read":3,"content":"abd"}' }
            { Receive-GuestFile -RemotePath 'C:\x\collect.b64' -Sha256 $script:AbcHash } |
                Should-Throw -ExceptionMessage ("*did not arrive intact: 3 characters with SHA-256 *" +
                    "the VM's copy has $($script:AbcHash)")
        }

        It 'fails with the host output when file-read fails' {
            Mock ssh { $global:LASTEXITCODE = 2; 'file not found' }
            { Receive-GuestFile -RemotePath 'C:\x\missing.b64' -Sha256 $script:AbcHash } |
                Should-Throw -ExceptionMessage '*file-read of C:\x\missing.b64 failed on pve: file not found'
        }
    }

    Context 'Expand-GzipText' {
        It 'turns the base64 of gzip of UTF-8 text back into the text' {
            $text = '{"NonAscii":"Gr' + [char]0xFC + [char]0xDF + 'e"}' + ('x' * 5000)
            $packed = [System.IO.MemoryStream]::new()
            $mode = [System.IO.Compression.CompressionMode]::Compress
            $gzip = [System.IO.Compression.GZipStream]::new($packed, $mode)
            $bytes = [Text.Encoding]::UTF8.GetBytes($text)
            $gzip.Write($bytes, 0, $bytes.Length)
            $gzip.Dispose()
            $encoded = [Convert]::ToBase64String($packed.ToArray())
            $encoded.Length | Should-BeLessThan $text.Length
            Expand-GzipText -Base64 $encoded | Should-Be $text
        }
    }

    Context 'Invoke-GuestScriptFile' {
        BeforeEach {
            # The delivery is Send-GuestFile's; the run call's stdout is what comes back
            Mock Send-GuestFile {
                $encoded = [Convert]::ToBase64String($Bytes)
                Add-Content -Path (Join-Path $TestDrive 'calls.log') -Value "send|$RemotePath|$encoded"
            }
            Mock Invoke-GuestPowerShell {
                Add-Content -Path (Join-Path $TestDrive 'calls.log') -Value $Script
                if ($Script -like "*& 'C:\ProgramData\IntuneScriptLab\*.ps1'") { 'ran' }
            }
        }

        It 'sends the script with a BOM through Send-GuestFile and runs it by path' {
            $body = 'Write-Output ' + ('x' * 2000)
            Invoke-GuestScriptFile -Script $body -TimeoutSeconds 60 | Should-Be 'ran'
            $calls = @(Get-CallLog)
            $calls[0] | Should-BeLikeString "send|C:\ProgramData\IntuneScriptLab\collect.ps1|*"
            $bytes = [Convert]::FromBase64String(($calls[0] -split '\|')[2])
            [Convert]::ToHexString($bytes[0..2]) | Should-Be 'EFBBBF'
            [Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3) | Should-Be $body
            $calls[-1] | Should-Be ('Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force; ' +
                "& 'C:\ProgramData\IntuneScriptLab\collect.ps1'")
        }

        It 'starts a detached script behind a started marker, so a launch that runs twice starts it once' {
            Mock Invoke-GuestPowerShell {
                Add-Content -Path (Join-Path $TestDrive 'calls.log') -Value $Script
                if ($Script -like "Test-Path -Path '*.done'") { 'True' }
                elseif ($Script -like "Get-Content -Path '*.out'*") { 'output' }
            }
            Invoke-GuestScriptFile -Script 'x' -Detach -TimeoutSeconds 60 | Should-Be 'output'

            $calls = [System.Collections.Generic.List[string]]@(Get-CallLog)
            $started = "'C:\ProgramData\IntuneScriptLab\collect.ps1.started'"
            $clear = "Remove-Item -Path $started -ErrorAction SilentlyContinue"
            $calls | Should-ContainCollection $clear
            $launch = @($calls | Where-Object { $_ -like '*Start-Process*' })
            $launch.Count | Should-Be 1
            $launch[0] | Should-BeLikeString ("if (-not (Test-Path -Path $started)) { Set-Content " +
                "-Path $started -Value started; *Start-Process -FilePath '*collect.ps1.cmd' -WindowStyle Hidden }")
            # The marker of an earlier run is cleared before the launch, not after it
            $calls.IndexOf($launch[0]) | Should-BeGreaterThan $calls.IndexOf($clear)
        }

        It 'names the remote file after -RemoteName' {
            $null = Invoke-GuestScriptFile -Script 'x' -RemoteName 'fixtures.ps1'
            $calls = @(Get-CallLog)
            $calls[0] | Should-BeLikeString 'send|C:\ProgramData\IntuneScriptLab\fixtures.ps1|*'
            $calls[-1] | Should-BeLikeString "*& 'C:\ProgramData\IntuneScriptLab\fixtures.ps1'"
        }

        It 'passes the run timeout to the run call' {
            Mock Invoke-GuestPowerShell {
                Add-Content -Path (Join-Path $TestDrive 'calls.log') -Value "$TimeoutSeconds|$Script"
            }
            $null = Invoke-GuestScriptFile -Script 'x' -TimeoutSeconds 777
            $calls = @(Get-CallLog)
            $calls[-1] | Should-BeLikeString "777|*& 'C:\ProgramData\IntuneScriptLab\collect.ps1'"
        }
    }
}
