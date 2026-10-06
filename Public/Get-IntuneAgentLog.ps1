function Get-IntuneAgentLog {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Reads the Intune Management Extension logs as objects, with the events the agent's lines record.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Read')]
    [OutputType('IntuneScriptLab.AgentLogEntry')]
    param(
        [Parameter(ParameterSetName = 'Read', Position = 0)]
        [string[]]$Path,

        [Parameter(ParameterSetName = 'Read')]
        [ValidateSet('Agent', 'AppWorkload', 'HealthScripts', 'AgentExecutor', 'All')]
        [string[]]$Log = @('Agent', 'AppWorkload', 'HealthScripts', 'AgentExecutor'),

        [Parameter(ParameterSetName = 'Read')]
        [string[]]$Id,

        [Parameter(ParameterSetName = 'Read')]
        [string[]]$EventName,

        [Parameter(ParameterSetName = 'Read')]
        [string]$Pattern,

        [Parameter(ParameterSetName = 'Read')]
        [ValidateSet('Information', 'Warning', 'Error')]
        [string[]]$Level,

        [Parameter(ParameterSetName = 'Read')]
        [datetime]$After,

        [Parameter(ParameterSetName = 'Read')]
        [datetime]$Before,

        [Parameter(ParameterSetName = 'Read')]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Last,

        [Parameter(ParameterSetName = 'List', Mandatory)]
        [switch]$ListEvent
    )
    Write-Verbose "Starting $($MyInvocation.MyCommand.Name) for $($PSBoundParameters.Keys -join ', ')"

    # Touching the table once compiles it, for -ListEvent and for validating -EventName
    $null = Get-IslAgentLogEvent -Message ''
    if ($ListEvent) {
        foreach ($definition in $script:IslAgentLogEvents) {
            [pscustomobject]@{
                PSTypeName = 'IntuneScriptLab.AgentLogEventDefinition'
                Event      = $definition.Event
                Pattern    = $definition.Regex.ToString()
            }
        }
        return
    }
    $knownEvents = @($script:IslAgentLogEvents | ForEach-Object { $_.Event })
    foreach ($name in $EventName) {
        if ($name -notin $knownEvents) {
            throw "Unknown event '$name'. Get-IntuneAgentLog -ListEvent shows the names"
        }
    }

    if (-not $Path) {
        $programData = if ($env:ProgramData) { $env:ProgramData } else { 'C:\ProgramData' }
        $Path = @(Join-Path -Path $programData -ChildPath 'Microsoft\IntuneManagementExtension\Logs')
    }
    $filters = @{
        Agent         = 'IntuneManagementExtension*.log'
        AppWorkload   = 'AppWorkload*.log'
        HealthScripts = 'HealthScripts*.log'
        AgentExecutor = 'AgentExecutor*.log'
        All           = '*.log'
    }
    $files = foreach ($item in $Path) {
        $resolved = (Resolve-Path -LiteralPath $item -ErrorAction Stop).ProviderPath
        if (Test-Path -LiteralPath $resolved -PathType Container) {
            foreach ($name in $Log) {
                Get-ChildItem -LiteralPath $resolved -Filter $filters[$name] -File | ForEach-Object { $_.FullName }
            }
        }
        else { $resolved }
    }
    $files = @($files | Sort-Object -Unique)
    if (-not $files) {
        Write-Warning "No log files under $($Path -join ', ')"
        return
    }

    # The parser applies the filters to the raw record, before it builds an entry; the event filter
    # waits for the classification, which runs once per file over every kept message rather than
    # once per entry
    $parseSplat = @{}
    foreach ($name in 'Level', 'After', 'Before', 'Pattern', 'Id') {
        if ($PSBoundParameters.ContainsKey($name)) { $parseSplat[$name] = $PSBoundParameters[$name] }
    }
    if ($EventName) {
        # A message that holds none of the wanted events' leading literals cannot be one of them.
        # One event without a literal (its pattern starts with a group) means no such shortcut
        $needles = @(foreach ($definition in $script:IslAgentLogEvents) {
                if ($definition.Event -in $EventName) { $definition.Needle }
            })
        if ($needles.Count -eq @($EventName | Select-Object -Unique).Count) { $parseSplat.Contains = $needles }
    }
    $entries = foreach ($file in $files) {
        # A file's last write is at or after its newest entry, so a rolled-over file written
        # before -After has nothing to give and is not read
        if ($PSBoundParameters.ContainsKey('After') -and (Get-Item -LiteralPath $file).LastWriteTime -lt $After) {
            Write-Verbose "Skipping $file, last written before $After"
            continue
        }
        Write-Verbose "Reading $file"
        $kept = @(ConvertFrom-IslCmTraceLog -Path $file @parseSplat)
        if (-not $kept.Count) { continue }
        $classified = @(Get-IslAgentLogEvent -Message @($kept | ForEach-Object { $_.Message }))
        for ($index = 0; $index -lt $kept.Count; $index++) {
            $entry = $kept[$index]
            $classification = $classified[$index]
            if ($EventName -and $classification.Event -notin $EventName) { continue }
            $entry.Event = $classification.Event
            $entry.Detail = $classification.Detail
            $entry.Id = $classification.Id
            $entry
        }
    }
    $entries = @($entries | Sort-Object -Property Time, Log, Line)
    if ($Last -and $entries.Count -gt $Last) {
        $entries = $entries[($entries.Count - $Last)..($entries.Count - 1)]
    }
    Write-Verbose "Completed $($MyInvocation.MyCommand.Name): $($entries.Count) entries from $($files.Count) files"
    $entries
}
