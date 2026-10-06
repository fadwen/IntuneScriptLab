# Running PowerShell inside a lab VM through the QEMU guest agent, over SSH to the Proxmox host.
# Dot-sourced by Invoke-ValidationRound.ps1 and Invoke-LabGuestScript.ps1, whose $ProxmoxHost and
# $VmId parameters the function reads, and kept apart from them so it can be unit-tested with ssh
# mocked and without the driver's #Requires lines.

function Invoke-GuestPowerShell {
    <#
    .SYNOPSIS
        Runs a PowerShell snippet as SYSTEM inside the VM and returns its stdout.

    .DESCRIPTION
        The guest agent starts a command and hands back its process id; the result is asked for by
        that id and stays with the agent until a status call collects it. Measured on the lab
        device (README.md, "Timing notes"):

        A result nobody collects is kept. Windows reuses process ids within minutes, and the agent
        answers a status call with the oldest result it holds for the id, so a later command given
        the same id got an earlier command's output: the right shape, the wrong content. A payload
        chunk replaced that way is what broke Collect on 2026-10-05. "qm guest exec" leaves such
        results behind whenever its own status poll times out while the command is still running.

        A status call that times out on the host has still been answered by the agent: if the
        command had finished, its result was handed over and is gone.

        So the command is started without waiting ("qm guest exec --synchronous 0"), its result is
        asked for by id until it arrives, and every command prints a marker of its own first. A
        reply without the marker is somebody else's result: asking for it collected it, and the
        next reply under the id is this command's. When the agent holds nothing for the id after a
        status call timed out, the result went with that call and the command is run again.

        A snippet therefore has to be safe to repeat, as before; what it can no longer do is come
        back with another command's output.

    .PARAMETER Script
        The PowerShell to run. A snippet, not a script with a param block: the marker line is put
        in front of it. The guest agent's command line fails silently above a few KB.

    .PARAMETER TimeoutSeconds
        How long to wait for the command to finish before giving up. Default 120.

    .EXAMPLE
        Invoke-GuestPowerShell -Script '(Get-Service IntuneManagementExtension).Status'

        The agent service's state on the VM named by the caller's $VmId.

    .OUTPUTS
        System.String. The command's stdout; its stderr and a non-zero exit become warnings.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Script,

        [int]$TimeoutSeconds = 120
    )

    $result = $null
    for ($run = 1; -not $result; $run++) {
        $marker = [guid]::NewGuid().ToString('N')
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("'$marker'`n$Script"))
        $processId = $null
        for ($attempt = 1; -not $processId; $attempt++) {
            $raw = ssh -o BatchMode=yes $ProxmoxHost ("qm guest exec $VmId --synchronous 0 -- powershell " +
                "-NoProfile -NonInteractive -EncodedCommand $encoded") 2>&1
            $text = ($raw -join "`n").Trim()
            if ($LASTEXITCODE -eq 0 -and $text -match '"pid"\s*:\s*(\d+)') { $processId = $Matches[1]; break }
            if ($attempt -ge 3) { throw "qm guest exec failed on ${ProxmoxHost}: $text" }
            Write-Warning "qm guest exec attempt $attempt on ${ProxmoxHost}: $text"
            Start-Sleep -Seconds 10
        }

        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        $unmarked = $null
        $replyLost = $false
        $failures = 0
        while (-not $result) {
            Start-Sleep -Seconds 1
            $raw = ssh -o BatchMode=yes $ProxmoxHost "qm guest exec-status $VmId $processId" 2>&1
            $text = ($raw -join "`n").Trim()
            if ($LASTEXITCODE -eq 0 -and $text.StartsWith('{')) {
                $failures = 0
                $reply = $text | ConvertFrom-Json
                if ($reply.exited) {
                    if ("$($reply.'out-data')".StartsWith($marker)) { $result = $reply; break }
                    # An earlier command's result under a reused process id; it is collected now
                    Write-Verbose "Process id $processId answered with another command's result; asking again"
                    $unmarked = $reply
                }
            }
            elseif ($text -match 'does not exist') {
                # Nothing more under this id. After a status call that timed out, the result went
                # with that call's reply: run the command again
                if ($replyLost) { break }
                # Otherwise the reply without the marker was this command's after all: powershell.exe
                # never reached the first line (a command line too long, for one)
                if (-not $unmarked) {
                    throw "The guest agent on VM $VmId holds no result for process id $processId"
                }
                $result = $unmarked
                break
            }
            else {
                $failures++
                $replyLost = $true
                if ($failures -ge 10) { throw "qm guest exec-status failed on ${ProxmoxHost}: $text" }
                Write-Verbose "qm guest exec-status attempt $failures on ${ProxmoxHost}: $text"
            }
            if ((Get-Date) -gt $deadline) {
                throw ("The guest command (process id $processId on VM $VmId) did not finish within " +
                    "$TimeoutSeconds s")
            }
        }
        if (-not $result) {
            if ($run -ge 3) { throw "The guest command's result was lost to a timed-out status call $run times" }
            Write-Warning ("The result of process id $processId went with a status call that timed out; " +
                'running the command again')
        }
    }

    $output = "$($result.'out-data')"
    if ($output.StartsWith($marker)) { $output = $output.Substring($marker.Length) -replace '^\r?\n', '' }

    # Windows PowerShell writes stderr as CLIXML: progress records ("Preparing modules for first
    # use") are noise, error records are what the caller needs to read
    $errorText = "$($result.'err-data')"
    if ($errorText -match '#< CLIXML') {
        $messages = foreach ($chunk in ($errorText -split '#< CLIXML')) {
            if (-not $chunk.Trim()) { continue }
            try {
                foreach ($item in [System.Management.Automation.PSSerializer]::Deserialize($chunk.Trim())) {
                    if ($item -is [string]) { $item }
                    elseif ($item.PSObject.TypeNames -match 'ErrorRecord') { "$item" }
                }
            }
            catch { $chunk.Trim() }
        }
        $errorText = ($messages -join "`n")
    }
    if ($result.exitcode -ne 0) { Write-Warning "Guest script exited $($result.exitcode): $errorText" }
    elseif ($errorText.Trim()) { Write-Warning $errorText.Trim() }
    elseif (-not $output) { Write-Verbose "Guest script produced no output (process id $processId)" }
    $output
}

function Send-GuestFile {
    <#
    .SYNOPSIS
        Writes a file into the VM through the guest agent's file-write call and checks its hash.

    .DESCRIPTION
        The agent's file-write call takes the content as text on the host's command line, about
        30,000 characters at a time here, against 1,200 per guest exec before (a 140 KB module zip
        went over as five parts in under a minute, where guest exec needs about 6 seconds per part).
        The bytes go as base64 in numbered part files, which a guest command joins, decodes and
        removes; a part written twice replaces itself. The VM's SHA-256 of the written file is
        compared with the local one.

    .PARAMETER RemotePath
        Where the file lands on the VM.

    .PARAMETER Bytes
        The file's bytes.

    .PARAMETER PartSize
        Base64 characters per file-write call. Default 30000, which keeps the whole ssh command
        line under the 32,767 characters Windows allows.

    .EXAMPLE
        Send-GuestFile -RemotePath 'C:\ProgramData\IntuneScriptLab\collect.ps1' -Bytes $bytes

        The script is on the VM, byte for byte.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$RemotePath,

        [Parameter(Mandatory)]
        [byte[]]$Bytes,

        [int]$PartSize = 30000
    )

    $null = Invoke-GuestPowerShell -Script ("`$null = New-Item -ItemType Directory -Path " +
        "'$(Split-Path -Path $RemotePath -Parent)' -Force; " +
        "Remove-Item -Path '$RemotePath.b64.*' -ErrorAction SilentlyContinue")
    $b64 = [Convert]::ToBase64String($Bytes)
    $index = 0
    for ($offset = 0; $offset -lt $b64.Length; $offset += $PartSize) {
        $part = $b64.Substring($offset, [Math]::Min($PartSize, $b64.Length - $offset))
        $partPath = '{0}.b64.{1:D4}' -f $RemotePath, $index++
        $command = "pvesh create /nodes/`$(hostname)/qemu/$VmId/agent/file-write " +
            "--file '$partPath' --content '$part'"
        $raw = ssh -o BatchMode=yes $ProxmoxHost $command 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "file-write of $partPath failed on ${ProxmoxHost}: $(($raw -join ' ').Trim())"
        }
    }
    $join = "`$parts = Get-ChildItem -Path '$RemotePath.b64.*' | Sort-Object Name | " +
        "ForEach-Object { (Get-Content -Path `$_.FullName -Raw).Trim() }; " +
        "[IO.File]::WriteAllBytes('$RemotePath', [Convert]::FromBase64String((-join `$parts))); " +
        "Remove-Item -Path '$RemotePath.b64.*'; (Get-FileHash -Path '$RemotePath' -Algorithm SHA256).Hash"
    $remoteHash = "$(Invoke-GuestPowerShell -Script $join)".Trim()
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $localHash = [BitConverter]::ToString($sha.ComputeHash($Bytes)) -replace '-', '' }
    finally { $sha.Dispose() }
    if ($remoteHash -ne $localHash) {
        throw "$RemotePath did not arrive intact: the VM hashes it $remoteHash, the local bytes hash $localHash"
    }
    Write-Verbose "Sent $($Bytes.Length) bytes to $RemotePath in $index part(s)"
}

function Receive-GuestFile {
    <#
    .SYNOPSIS
        Reads a text file from the VM in one guest agent call and checks it against the VM's hash.

    .DESCRIPTION
        The agent's file-read call returns a file of up to 16 MB in one reply; 507,000 characters
        came back in 2 seconds, where reading the same text through guest exec took 179 calls of
        100,000 characters. The text is hashed and compared with the SHA-256 the VM computed over
        its copy, so a reply that is not the file is refused with both hashes rather than found
        as a parse error later.

    .PARAMETER RemotePath
        The file on the VM. ASCII text, base64 as the collect script writes it.

    .PARAMETER Sha256
        The SHA-256 of its text as the VM computed it, in hex.

    .EXAMPLE
        Receive-GuestFile -RemotePath 'C:\ProgramData\IntuneScriptLab\collect.b64' -Sha256 $hash

        The file's text, or an error naming both hashes when it did not arrive intact.

    .OUTPUTS
        System.String.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$RemotePath,

        [Parameter(Mandatory)]
        [string]$Sha256
    )

    $command = "pvesh get /nodes/`$(hostname)/qemu/$VmId/agent/file-read --file '$RemotePath' --output-format json"
    $raw = ssh -o BatchMode=yes $ProxmoxHost $command 2>&1
    $text = ($raw -join "`n").Trim()
    if ($LASTEXITCODE -ne 0 -or -not $text.StartsWith('{')) {
        throw "file-read of $RemotePath failed on ${ProxmoxHost}: $text"
    }
    $reply = $text | ConvertFrom-Json
    if ($reply.truncated) {
        throw "$RemotePath is longer than the 16 MB the guest agent's file-read call returns"
    }
    $content = "$($reply.content)"
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha.ComputeHash([Text.Encoding]::ASCII.GetBytes($content))
        $actual = [BitConverter]::ToString($digest) -replace '-', ''
    }
    finally { $sha.Dispose() }
    if ($actual -ne $Sha256) {
        throw ("$RemotePath did not arrive intact: $($content.Length) characters with SHA-256 $actual, " +
            "the VM's copy has $Sha256")
    }
    $content
}
