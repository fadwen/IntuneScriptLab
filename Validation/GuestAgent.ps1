# Running PowerShell inside a lab VM through the QEMU guest agent, over SSH to the Proxmox host.
# Dot-sourced by Invoke-ValidationRound.ps1 and Invoke-LabGuestScript.ps1, whose $ProxmoxHost and
# $VmId parameters the function reads, and kept apart from them so it can be unit-tested with ssh
# mocked and without the driver's #Requires lines.


function Get-GuestReplyProperty {
    <#
    .SYNOPSIS
        Gets one property of a guest agent reply, or nothing when the reply lacks it.

    .DESCRIPTION
        The agent leaves a key out of its JSON reply when it has nothing for it: out-data for a command
        that printed nothing, err-data for one that wrote no errors, exitcode while the command still
        runs, truncated for a file that fit. Member access on such a reply is an error under strict
        mode, so every read of a reply goes through this function, which returns $null for a missing
        reply, key or property, from a dictionary and an object alike.

    .PARAMETER Reply
        The reply, as ConvertFrom-Json returns it.

    .PARAMETER Name
        The name of the property, such as 'out-data'.

    .EXAMPLE
        Get-GuestReplyProperty -Reply ('{"exited":1,"exitcode":0}' | ConvertFrom-Json) -Name 'out-data'

        Returns $null, because the reply has no out-data.

    .INPUTS
        None.

    .OUTPUTS
        System.Object. The value of the property, or $null.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Reply,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $Reply) {
        return $null
    }
    if ($Reply -is [System.Collections.IDictionary]) {
        if ($Reply.Contains($Name)) {
            return $Reply[$Name]
        }
        return $null
    }
    $property = $Reply.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    $property.Value
}


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

        The host and the VM are the caller's $ProxmoxHost and $VmId. A start that fails three
        times, a status call that fails ten times, a command that does not finish in time, a
        result lost three times and a process id the agent holds nothing for are terminating
        errors.

    .PARAMETER Script
        The PowerShell to run. A snippet, not a script with a param block: the marker line is put
        in front of it. The guest agent's command line fails silently above a few KB.

    .PARAMETER TimeoutSeconds
        How long to wait for the command to finish before giving up. Default 120.

    .EXAMPLE
        Invoke-GuestPowerShell -Script '(Get-Service IntuneManagementExtension).Status'

        The agent service's state on the VM named by the caller's $VmId.

    .INPUTS
        None.

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
            if ($attempt -ge 3) {
                $message = "qm guest exec failed on ${ProxmoxHost}: $text"
                $exception = [System.InvalidOperationException]::new($message)
                $category = [System.Management.Automation.ErrorCategory]::ConnectionError
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception, 'GuestExecStartFailed', $category, $VmId)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
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
                if (Get-GuestReplyProperty -Reply $reply -Name 'exited') {
                    $replyOutput = "$(Get-GuestReplyProperty -Reply $reply -Name 'out-data')"
                    if ($replyOutput.StartsWith($marker)) { $result = $reply; break }
                    # An earlier command's result under a reused process id; it is collected now
                    Write-Verbose "Process id $processId answered with another command's result; asking again"
                    $unmarked = $reply
                }
            } elseif ($text -match 'does not exist') {
                # Nothing more under this id. After a status call that timed out, the result went
                # with that call's reply: run the command again
                if ($replyLost) { break }
                # Otherwise the reply without the marker was this command's after all: powershell.exe
                # never reached the first line (a command line too long, for one)
                if (-not $unmarked) {
                    $message = "The guest agent on VM $VmId holds no result for process id $processId"
                    $exception = [System.InvalidOperationException]::new($message)
                    $category = [System.Management.Automation.ErrorCategory]::ObjectNotFound
                    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                        $exception, 'GuestResultMissing', $category, $processId)
                    $PSCmdlet.ThrowTerminatingError($errorRecord)
                }
                $result = $unmarked
                break
            } else {
                $failures++
                $replyLost = $true
                if ($failures -ge 10) {
                    $message = "qm guest exec-status failed on ${ProxmoxHost}: $text"
                    $exception = [System.InvalidOperationException]::new($message)
                    $category = [System.Management.Automation.ErrorCategory]::ConnectionError
                    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                        $exception, 'GuestExecStatusFailed', $category, $processId)
                    $PSCmdlet.ThrowTerminatingError($errorRecord)
                }
                Write-Verbose "qm guest exec-status attempt $failures on ${ProxmoxHost}: $text"
            }
            if ((Get-Date) -gt $deadline) {
                $message = ("The guest command (process id $processId on VM $VmId) did not finish within " +
                    "$TimeoutSeconds s")
                $exception = [System.TimeoutException]::new($message)
                $category = [System.Management.Automation.ErrorCategory]::OperationTimeout
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception, 'GuestCommandTimedOut', $category, $processId)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
        }
        if (-not $result) {
            if ($run -ge 3) {
                $message = "The guest command's result was lost to a timed-out status call $run times"
                $exception = [System.InvalidOperationException]::new($message)
                $category = [System.Management.Automation.ErrorCategory]::InvalidResult
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception, 'GuestResultLost', $category, $VmId)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
            Write-Warning ("The result of process id $processId went with a status call that timed out; " +
                'running the command again')
        }
    }

    $output = "$(Get-GuestReplyProperty -Reply $result -Name 'out-data')"
    if ($output.StartsWith($marker)) { $output = $output.Substring($marker.Length) -replace '^\r?\n', '' }

    # Windows PowerShell writes stderr as CLIXML: progress records ("Preparing modules for first
    # use") are noise, error records are what the caller needs to read
    $errorText = "$(Get-GuestReplyProperty -Reply $result -Name 'err-data')"
    if ($errorText -match '#< CLIXML') {
        $messages = foreach ($chunk in ($errorText -split '#< CLIXML')) {
            if (-not $chunk.Trim()) { continue }
            try {
                foreach ($item in [System.Management.Automation.PSSerializer]::Deserialize($chunk.Trim())) {
                    if ($item -is [string]) {
                        $item
                    } elseif ($item.PSObject.TypeNames -match 'ErrorRecord') {
                        "$item"
                    }
                }
            } catch {
                # A chunk that is not CLIXML is stderr as the guest wrote it, and the caller still
                # needs to read it, so the text itself goes into the warning
                $chunk.Trim()
            }
        }
        $errorText = ($messages -join "`n")
    }
    $exitCode = Get-GuestReplyProperty -Reply $result -Name 'exitcode'
    if ($exitCode -ne 0) {
        Write-Warning "Guest script exited ${exitCode}: $errorText"
    } elseif ($errorText.Trim()) {
        Write-Warning $errorText.Trim()
    } elseif (-not $output) {
        Write-Verbose "Guest script produced no output (process id $processId)"
    }
    $output
}


function Send-GuestFile {
    <#
    .SYNOPSIS
        Writes a file into the VM through the guest agent and checks its hash.

    .DESCRIPTION
        Writes a file into the VM through the guest agent's file-write call and checks its hash.

        The agent's file-write call takes the content as text on the host's command line, about
        30,000 characters at a time here, against 1,200 per guest exec before (a 140 KB module zip
        went over as five parts in under a minute, where guest exec needs about 6 seconds per part).
        The bytes go as base64 in numbered part files, which a guest command joins, decodes and
        removes; a part written twice replaces itself. The VM's SHA-256 of the written file is
        compared with the local one.

        A file-write the host refuses, a guest command that fails and a hash that differs are
        terminating errors.

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

    .INPUTS
        None.

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

    try {
        # Split-Path has no -LiteralPath together with -Parent; -Parent only cuts the string
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
                $message = "file-write of $partPath failed on ${ProxmoxHost}: $(($raw -join ' ').Trim())"
                $exception = [System.InvalidOperationException]::new($message)
                $category = [System.Management.Automation.ErrorCategory]::WriteError
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception, 'GuestFileWriteFailed', $category, $partPath)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
        }
        $join = "`$parts = Get-ChildItem -Path '$RemotePath.b64.*' | Sort-Object Name | " +
        "ForEach-Object { (Get-Content -Path `$_.FullName -Raw).Trim() }; " +
        "[IO.File]::WriteAllBytes('$RemotePath', [Convert]::FromBase64String((-join `$parts))); " +
        "Remove-Item -Path '$RemotePath.b64.*'; (Get-FileHash -Path '$RemotePath' -Algorithm SHA256).Hash"
        $remoteHash = "$(Invoke-GuestPowerShell -Script $join)".Trim()
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $localHash = [BitConverter]::ToString($sha.ComputeHash($Bytes)) -replace '-', ''
    } finally {
        $sha.Dispose()
    }
    if ($remoteHash -ne $localHash) {
        $message = ("$RemotePath did not arrive intact: the VM hashes it $remoteHash, " +
            "the local bytes hash $localHash")
        $exception = [System.IO.InvalidDataException]::new($message)
        $category = [System.Management.Automation.ErrorCategory]::InvalidResult
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception, 'GuestFileCorrupted', $category, $RemotePath)
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }
    Write-Verbose "Sent $($Bytes.Length) bytes to $RemotePath in $index part(s)"
}


function Receive-GuestFile {
    <#
    .SYNOPSIS
        Reads a text file from the VM in one guest agent call and checks its hash.

    .DESCRIPTION
        Reads a text file from the VM in one guest agent call and checks it against the VM's hash.

        The agent's file-read call returns a file of up to 16 MB in one reply; 507,000 characters
        came back in 2 seconds, where reading the same text through guest exec took 179 calls of
        100,000 characters. The text is hashed and compared with the SHA-256 the VM computed over
        its copy, so a reply that is not the file is refused with both hashes rather than found
        as a parse error later.

        A file-read the host refuses, a reply the agent marked truncated and a hash that differs
        are terminating errors.

    .PARAMETER RemotePath
        The file on the VM. ASCII text, base64 as the collect script writes it.

    .PARAMETER Sha256
        The SHA-256 of its text as the VM computed it, in hex.

    .EXAMPLE
        Receive-GuestFile -RemotePath 'C:\ProgramData\IntuneScriptLab\collect.b64' -Sha256 $hash

        The file's text, or an error naming both hashes when it did not arrive intact.

    .INPUTS
        None.

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

    $command = ("pvesh get /nodes/`$(hostname)/qemu/$VmId/agent/file-read --file '$RemotePath' " +
        '--output-format json')
    $raw = ssh -o BatchMode=yes $ProxmoxHost $command 2>&1
    $text = ($raw -join "`n").Trim()
    if ($LASTEXITCODE -ne 0 -or -not $text.StartsWith('{')) {
        $message = "file-read of $RemotePath failed on ${ProxmoxHost}: $text"
        $exception = [System.InvalidOperationException]::new($message)
        $category = [System.Management.Automation.ErrorCategory]::ReadError
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception, 'GuestFileReadFailed', $category, $RemotePath)
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }
    $reply = $text | ConvertFrom-Json
    if (Get-GuestReplyProperty -Reply $reply -Name 'truncated') {
        $message = "$RemotePath is longer than the 16 MB the guest agent's file-read call returns"
        $exception = [System.InvalidOperationException]::new($message)
        $category = [System.Management.Automation.ErrorCategory]::LimitsExceeded
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception, 'GuestFileTooLarge', $category, $RemotePath)
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }
    $content = "$(Get-GuestReplyProperty -Reply $reply -Name 'content')"
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha.ComputeHash([Text.Encoding]::ASCII.GetBytes($content))
        $actual = [BitConverter]::ToString($digest) -replace '-', ''
    } finally {
        $sha.Dispose()
    }
    if ($actual -ne $Sha256) {
        $message = ("$RemotePath did not arrive intact: $($content.Length) characters with SHA-256 $actual, " +
            "the VM's copy has $Sha256")
        $exception = [System.IO.InvalidDataException]::new($message)
        $category = [System.Management.Automation.ErrorCategory]::InvalidResult
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception, 'GuestFileCorrupted', $category, $RemotePath)
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }
    $content
}
