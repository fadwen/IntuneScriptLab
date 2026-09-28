function Get-IntuneAgentTimeline {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        One timeline per policy or app from the agent's logs: the steps it went through and how they ended.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.AgentTimeline')]
    param(
        [Parameter(Position = 0)]
        [string[]]$Path,

        [ValidateSet('Agent', 'AppWorkload', 'HealthScripts', 'AgentExecutor', 'All')]
        [string[]]$Log = @('Agent', 'AppWorkload', 'HealthScripts', 'AgentExecutor'),

        [string[]]$Id,

        [datetime]$After,

        [datetime]$Before
    )
    Write-Verbose "Starting $($MyInvocation.MyCommand.Name)"

    $logSplat = @{ Log = $Log }
    if ($Path) { $logSplat.Path = $Path }
    if ($Id) { $logSplat.Id = $Id }
    if ($PSBoundParameters.ContainsKey('After')) { $logSplat.After = $After }
    if ($PSBoundParameters.ContainsKey('Before')) { $logSplat.Before = $Before }
    $entries = @(Get-IntuneAgentLog @logSplat)

    # App names travel in the policy list the agent logs; nothing else names a policy
    $names = @{}
    foreach ($entry in ($entries | Where-Object Event -eq 'AppPolicyFetch')) {
        foreach ($match in [regex]::Matches($entry.Message, '"Id":"([0-9a-fA-F-]{36})","Name":"([^"]*)"')) {
            $names[$match.Groups[1].Value.ToLower()] = $match.Groups[2].Value
        }
    }

    $launches = 'RemediationStart', 'ScriptPolicyStart', 'AppExecution'
    $results = 'RemediationReport', 'DetectionResult', 'ScriptPolicyResult', 'ScriptExit', 'AppReport',
    'AppInstallOutcome', 'AppDetection', 'AppApplicability', 'EspAppState'
    $kindByLog = @{ HealthScripts = 'Remediation'; AppWorkload = 'Win32App' }

    $timelines = foreach ($group in ($entries | Where-Object { $_.Event -and $_.Id } | Group-Object Id)) {
        $steps = @($group.Group | Sort-Object Time, Log, Line | ForEach-Object {
                [pscustomobject]@{
                    PSTypeName = 'IntuneScriptLab.AgentTimelineStep'
                    Time       = $_.Time
                    Log        = $_.Log
                    Event      = $_.Event
                    Detail     = $_.Detail
                    Message    = $_.Message
                }
            })
        $logsSeen = @($steps | ForEach-Object { $_.Log -replace '-\d+$', '' } | Sort-Object -Unique)
        $kind = 'Unknown'
        foreach ($seen in $logsSeen) {
            if ($kindByLog.ContainsKey($seen)) { $kind = $kindByLog[$seen]; break }
        }
        if ($kind -eq 'Unknown' -and ($steps | Where-Object Event -like 'Script*')) { $kind = 'PlatformScript' }
        $lastResult = $steps | Where-Object Event -in $results | Select-Object -Last 1
        $outcome = if ($lastResult) { "$($lastResult.Event) $($lastResult.Detail)".Trim() } else { '' }
        $started = $steps[0].Time
        $ended = $steps[-1].Time
        $summaryParts = foreach ($step in $steps) {
            $label = if ($step.Detail) { "$($step.Event) $($step.Detail)" } else { $step.Event }
            "$($step.Time.ToString('HH:mm:ss')) $label"
        }
        $key = "$($group.Name)".ToLower()
        [pscustomobject]@{
            PSTypeName = 'IntuneScriptLab.AgentTimeline'
            Id         = $group.Name
            Name       = if ($names.ContainsKey($key)) { $names[$key] } else { $group.Name }
            Kind       = $kind
            Started    = $started
            Ended      = $ended
            Duration   = $ended - $started
            Runs       = @($steps | Where-Object Event -in $launches).Count
            Outcome    = $outcome
            Steps      = $steps
            Summary    = ($summaryParts -join ' > ')
        }
    }
    $timelines | Sort-Object Started
    Write-Verbose "Completed $($MyInvocation.MyCommand.Name)"
}
