function Get-IslAgentLogEvent {
    <#
    .SYNOPSIS
        Names the event that an agent log message records, as the experiments found.

    .DESCRIPTION
        A table of message patterns for the four Intune Management Extension logs, each pattern a
        line that marked a step in the validation rounds (Validation\Findings.md): the script policy
        fetch and its download count, a remediation's schedule inspection, start, detection result
        and report, a Win32 app's policy fetch, applicability, detection, rule evaluation, install
        and report, AgentExecutor's launch, exit code and output, and the Enrollment Status Page's
        phase, selected apps, registrations, tracked install states and completion (round 8).
        Anything else has no event.

        Returns the event name, a Detail string built from the pattern's capture groups (the
        exit code, the detection state, the download count) and the first GUID in the message,
        which is the policy or app id on every line that carries one. The compiled table is kept
        in the module scope as IslAgentLogEvents for Get-IntuneAgentLog -ListEvent.

    .PARAMETER Message
        The log entries' messages; one result per message, in the same order. A call per entry
        costs more than the classification, so Get-IntuneAgentLog sends a log's messages in one.

    .EXAMPLE
        Get-IslAgentLogEvent -Message 'Powershell execution is done, exitCode = 1'

        Event ScriptExit with Detail 1.

    .INPUTS
        None.

    .OUTPUTS
        IntuneScriptLab.AgentLogEvent.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.AgentLogEvent')]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [string[]]$Message
    )

    if (-not $script:IslAgentLogEvents) {
        # The table is Data\AgentLogEvents.psd1, read when the module is imported. A pattern too long
        # for one line there is an array of parts, joined here
        $definitions = $script:IslAgentLogEventDefinitions
        # One expression for the whole table: 44 patterns tried one by one cost 44 statements a
        # message, which was most of what reading a log cost; one Match is one. Alternation keeps
        # the table's order at a given position, so two patterns that fit the same text still
        # resolve to the earlier one
        $singleline = [System.Text.RegularExpressions.RegexOptions]::Singleline
        $combined = [System.Text.StringBuilder]::new()
        $position = 0
        $script:IslAgentLogEvents = @(foreach ($definition in $definitions) {
                # The literal text a pattern starts with, which a matching message must contain
                # somewhere: cheaper to look for than to run the pattern, and most messages match
                # no pattern at all
                $pattern = -join @($definition.Pattern)
                $prefix = Get-IslRegexLiteralPrefix -Pattern $pattern
                $group = "e$position"
                $renamed = ConvertTo-IslNamedGroupPattern -Pattern $pattern -Prefix "${group}g"
                if ($position -gt 0) { $null = $combined.Append('|') }
                $null = $combined.Append("(?<$group>").Append($renamed.Pattern).Append(')')
                $position++
                [pscustomobject]@{
                    Event = $definition.Event
                    Regex = [regex]::new($pattern, $singleline)
                    Needle = if ($prefix.Length -ge 3) { $prefix } else { $null }
                    Group = $group
                    Captures = $renamed.Count
                }
            })
        $script:IslAgentLogEventByGroup = @{}
        foreach ($definition in $script:IslAgentLogEvents) {
            $script:IslAgentLogEventByGroup[$definition.Group] = $definition
        }
        $compiled = $singleline -bor [System.Text.RegularExpressions.RegexOptions]::Compiled
        $script:IslAgentLogEventRegex = [regex]::new($combined.ToString(), $compiled)
    }

    $combinedRegex = $script:IslAgentLogEventRegex
    $byGroup = $script:IslAgentLogEventByGroup
    $firstSuccess = $script:IslAgentLogFirstSuccess
    # The policy or app id is the first GUID that is not the empty one: the device's user id on a
    # userless check-in is 00000000-... and comes before the policy id on some lines
    $guidRegex = $script:IslAgentLogGuidRegex
    foreach ($text in $Message) {
        $eventName = $null
        $detail = $null
        $match = $combinedRegex.Match($text)
        if ($match.Success) {
            # Group 0 is the whole match; the first successful group after it is the alternative
            $winner = & $firstSuccess $match.Groups
            $definition = $byGroup[$winner.Name]
            $eventName = $definition.Event
            $groups = @(for ($i = 1; $i -le $definition.Captures; $i++) {
                    $match.Groups["$($definition.Group)g$i"].Value.Trim()
                })
            $detail = ($groups | Where-Object { $_ }) -join ' '
            if (-not $detail) { $detail = $null }
        }
        $id = $null
        # A GUID has four hyphens; a message without one has no id to look for
        if ($text.IndexOf('-') -ge 0) {
            foreach ($match in $guidRegex.Matches($text)) {
                $candidate = $match.Value.ToLower()
                if ($null -eq $id) { $id = $candidate }
                if ($candidate -ne '00000000-0000-0000-0000-000000000000') { $id = $candidate; break }
            }
        }

        [pscustomobject]@{
            PSTypeName = 'IntuneScriptLab.AgentLogEvent'
            Event = $eventName
            Detail = $detail
            Id = $id
        }
    }
}


# The event table, compiled by the first call of Get-IslAgentLogEvent. It is assigned here so
# that the test for it in the function reads a variable that exists, which strict mode requires.
$script:IslAgentLogEvents = $null

$script:IslAgentLogGuidRegex = [regex]::new(
    '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
    [System.Text.RegularExpressions.RegexOptions]::Compiled)

# The first group after group 0 that took part in a match, found without a PowerShell loop over the
# groups: Enumerable.Skip(1) then FirstOrDefault with Group.Success as the predicate. The generic
# methods are closed by reflection once, because Windows PowerShell 5.1 has no syntax for it, and
# GroupCollection is cast to IEnumerable<Group> first because .NET Framework's is not one
$script:IslAgentLogFirstSuccess = & {
    $groupType = [System.Text.RegularExpressions.Group]
    $enumerable = [System.Linq.Enumerable]
    $cast = $enumerable.GetMethod('Cast').MakeGenericMethod($groupType)
    $skip = ($enumerable.GetMethods() | Where-Object {
            $_.Name -eq 'Skip' -and $_.GetParameters()[1].ParameterType -eq [int]
        } | Select-Object -First 1).MakeGenericMethod($groupType)
    $first = ($enumerable.GetMethods() | Where-Object {
            $_.Name -eq 'FirstOrDefault' -and $_.GetParameters().Count -eq 2 -and
            $_.GetParameters()[1].ParameterType.Name -like 'Func*'
        } | Select-Object -First 1).MakeGenericMethod($groupType)
    $success = [System.Delegate]::CreateDelegate([System.Func[System.Text.RegularExpressions.Group, bool]],
        $groupType.GetProperty('Success').GetGetMethod())
    {
        param($Groups)
        # Argument arrays built by hand: PowerShell would enumerate the collection into @()
        $castArguments = [object[]]::new(1)
        $castArguments[0] = $Groups
        $skipArguments = [object[]]::new(2)
        $skipArguments[0] = $cast.Invoke($null, $castArguments)
        $skipArguments[1] = 1
        $firstArguments = [object[]]::new(2)
        $firstArguments[0] = $skip.Invoke($null, $skipArguments)
        $firstArguments[1] = $success
        $first.Invoke($null, $firstArguments)
    }.GetNewClosure()
}
