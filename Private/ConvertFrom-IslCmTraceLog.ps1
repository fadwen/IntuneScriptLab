function ConvertFrom-IslCmTraceLog {
    <#
    .SYNOPSIS
        Parses a CMTrace-format log (the Intune Management Extension's) into entries.

    .DESCRIPTION
        The agent's logs are CMTrace lines: <![LOG[message]LOG]!><time="..." date="..."
        component="..." context="" type="1" thread="..." file="">. A message can span lines, the
        time carries seven fractional digits and sometimes a UTC bias suffix, and the date is
        M-d-yyyy. The file is opened with shared read/write access because the agent keeps it open
        for writing; a plain ReadAllText fails on a live log.

        Returns one IntuneScriptLab.AgentLogEntry per entry, in file order: Time (local, as the
        agent wrote it), Level (Information, Warning, Error from type 1, 2, 3), Component, Thread,
        Message, Log (the file's base name) and Line (the line the entry starts on). Event, Detail
        and Id are left empty for Get-IntuneAgentLog to fill.

    .PARAMETER Path
        The log file to parse.

    .EXAMPLE
        ConvertFrom-IslCmTraceLog -Path 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\HealthScripts.log'

        Every entry of the remediation log as objects.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.AgentLogEntry')]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $file = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    $stream = [System.IO.File]::Open($file, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite)
    try {
        $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8, $true)
        $text = $reader.ReadToEnd()
    }
    finally {
        $stream.Dispose()
    }

    $levels = @{ '1' = 'Information'; '2' = 'Warning'; '3' = 'Error' }
    $logName = [System.IO.Path]::GetFileNameWithoutExtension($file)
    $entryPattern = '<!\[LOG\[(?<message>.*?)\]LOG\]!><time="(?<time>[^"]*)" date="(?<date>[^"]*)"' +
        '(?<attributes>[^>]*)>'
    $entryRegex = [regex]::new($entryPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $line = 1
    $scanned = 0
    foreach ($match in $entryRegex.Matches($text)) {
        # Line numbers accumulate as the matches advance, so the text is scanned once
        while ($true) {
            $newline = $text.IndexOf("`n", $scanned, $match.Index - $scanned)
            if ($newline -lt 0) { break }
            $line++
            $scanned = $newline + 1
        }
        $scanned = $match.Index
        $attributes = $match.Groups['attributes'].Value
        $component = if ($attributes -match 'component="([^"]*)"') { $Matches[1] } else { '' }
        $type = if ($attributes -match 'type="(\d)"') { $Matches[1] } else { '1' }
        $thread = if ($attributes -match 'thread="(\d+)"') { [int]$Matches[1] } else { $null }
        $timeSplat = @{ Time = $match.Groups['time'].Value; Date = $match.Groups['date'].Value }
        [pscustomobject]@{
            PSTypeName = 'IntuneScriptLab.AgentLogEntry'
            Time       = ConvertTo-IslCmTraceTime @timeSplat
            Level      = if ($levels.ContainsKey($type)) { $levels[$type] } else { 'Information' }
            Component  = $component
            Thread     = $thread
            Event      = $null
            Detail     = $null
            Id         = $null
            Message    = $match.Groups['message'].Value.TrimEnd("`r", "`n")
            Log        = $logName
            Line       = $line
        }
    }
}
