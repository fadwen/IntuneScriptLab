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

    $idPatterns = @(foreach ($value in $Id) { [regex]::Escape($value) })
    $entries = foreach ($file in $files) {
        Write-Verbose "Reading $file"
        foreach ($entry in ConvertFrom-IslCmTraceLog -Path $file) {
            if ($Level -and $entry.Level -notin $Level) { continue }
            if ($PSBoundParameters.ContainsKey('After') -and $entry.Time -lt $After) { continue }
            if ($PSBoundParameters.ContainsKey('Before') -and $entry.Time -ge $Before) { continue }
            if ($Pattern -and $entry.Message -notmatch $Pattern) { continue }
            if ($idPatterns.Count) {
                $found = $false
                foreach ($idPattern in $idPatterns) {
                    if ($entry.Message -imatch $idPattern) { $found = $true; break }
                }
                if (-not $found) { continue }
            }
            $classified = Get-IslAgentLogEvent -Message $entry.Message
            if ($EventName -and $classified.Event -notin $EventName) { continue }
            $entry.Event = $classified.Event
            $entry.Detail = $classified.Detail
            $entry.Id = $classified.Id
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
