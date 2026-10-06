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

        The filters are the ones Get-IntuneAgentLog offers, applied to the raw record before an
        object is built for it. Building the object is most of what an entry costs, so a filtered
        read of a 22 MB log takes seconds where building every entry takes a minute.

    .PARAMETER Path
        The log file to parse.

    .PARAMETER Level
        Keep entries of these levels only: Information, Warning, Error.

    .PARAMETER After
        Keep entries at or after this local time.

    .PARAMETER Before
        Keep entries before this local time.

    .PARAMETER Pattern
        Keep entries whose message matches this regular expression, case-insensitive like -match.

    .PARAMETER Id
        Keep entries whose message contains any of these strings, case-insensitive; a policy or
        app id, usually.

    .PARAMETER Contains
        Keep entries whose message contains any of these strings, case-sensitive. Get-IntuneAgentLog
        passes the literal text the wanted events' patterns start with, so a message that can match
        none of them is dropped before the pattern runs.

    .EXAMPLE
        ConvertFrom-IslCmTraceLog -Path 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\HealthScripts.log'

        Every entry of the remediation log as objects.

    .EXAMPLE
        ConvertFrom-IslCmTraceLog -Path .\AppWorkload.log -Id 9b6543c3-6d66-4cfb-a8fb-d780079278f6 -Level Error

        The error entries that mention the app, without building the others.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.AgentLogEntry')]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [ValidateSet('Information', 'Warning', 'Error')]
        [string[]]$Level,

        [datetime]$After,

        [datetime]$Before,

        [string]$Pattern,

        [string[]]$Id,

        [string[]]$Contains
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
    $wantedTypes = if ($Level) { @($levels.Keys | Where-Object { $levels[$_] -in $Level }) } else { $null }
    $hasAfter = $PSBoundParameters.ContainsKey('After')
    $hasBefore = $PSBoundParameters.ContainsKey('Before')
    $ordinalIgnoreCase = [System.StringComparison]::OrdinalIgnoreCase
    $ordinal = [System.StringComparison]::Ordinal

    # An agent log of 22 MB is 80,000 entries, and every statement here runs once per entry. The
    # attributes come out of one compiled regex in the order the agent writes them, the timestamp
    # is read the way ConvertTo-IslCmTraceTime reads it without the call, and the filters run on
    # the raw strings before anything is built. Lines are counted only up to an entry that is kept
    $attributeRegex = $script:IslCmTraceAttributeRegex
    $timeFormat = $script:IslCmTraceTimeFormat
    $invariant = [cultureinfo]::InvariantCulture
    $noStyle = [System.Globalization.DateTimeStyles]::None
    $biasChars = [char[]]@('+', '-')
    $logName = [System.IO.Path]::GetFileNameWithoutExtension($file)
    $entryPattern = '<!\[LOG\[(?<message>.*?)\]LOG\]!><time="(?<time>[^"]*)" date="(?<date>[^"]*)"' +
        '(?<attributes>[^>]*)>'
    $entryRegex = [regex]::new($entryPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $line = 1
    $counted = 0
    foreach ($match in $entryRegex.Matches($text)) {
        $groups = $match.Groups
        $attributeMatch = $attributeRegex.Match($groups['attributes'].Value)
        $type = if ($attributeMatch.Success) { $attributeMatch.Groups[2].Value } else { '1' }
        if ($wantedTypes -and $type -notin $wantedTypes) { continue }

        $message = $groups['message'].Value
        if ($Pattern -and $message -notmatch $Pattern) { continue }
        if ($Id) {
            $mentioned = $false
            foreach ($value in $Id) {
                if ($message.IndexOf($value, $ordinalIgnoreCase) -ge 0) { $mentioned = $true; break }
            }
            if (-not $mentioned) { continue }
        }
        if ($Contains) {
            $present = $false
            foreach ($value in $Contains) {
                if ($message.IndexOf($value, $ordinal) -ge 0) { $present = $true; break }
            }
            if (-not $present) { continue }
        }

        $timeText = $groups['time'].Value
        $bias = $timeText.IndexOfAny($biasChars, [Math]::Min(7, $timeText.Length))
        if ($bias -ge 0) { $timeText = $timeText.Substring(0, $bias) }
        $time = [datetime]::MinValue
        $stamp = "$($groups['date'].Value) $timeText"
        if (-not [datetime]::TryParseExact($stamp, $timeFormat, $invariant, $noStyle, [ref]$time)) {
            throw "Not a CMTrace timestamp: $stamp ($file)"
        }
        if ($hasAfter -and $time -lt $After) { continue }
        if ($hasBefore -and $time -ge $Before) { continue }

        # The newlines between the last kept entry and this one, in one .NET call
        if ($match.Index -gt $counted) {
            $line += $text.Substring($counted, $match.Index - $counted).Split("`n").Length - 1
            $counted = $match.Index
        }
        [pscustomobject]@{
            PSTypeName = 'IntuneScriptLab.AgentLogEntry'
            Time       = $time
            Level      = if ($levels.ContainsKey($type)) { $levels[$type] } else { 'Information' }
            Component  = if ($attributeMatch.Success) { $attributeMatch.Groups[1].Value } else { '' }
            Thread     = if ($attributeMatch.Success) { [int]$attributeMatch.Groups[3].Value } else { $null }
            Event      = $null
            Detail     = $null
            Id         = $null
            Message    = $message.TrimEnd("`r", "`n")
            Log        = $logName
            Line       = $line
        }
    }
}

# component, then type, then thread, in the order every agent log writes them; context and file
# sit between and after them and are not read
$script:IslCmTraceAttributeRegex = [regex]::new('component="([^"]*)".*?type="(\d)".*?thread="(\d+)"',
    [System.Text.RegularExpressions.RegexOptions]::Compiled)
