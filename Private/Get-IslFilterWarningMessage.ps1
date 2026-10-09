function Get-IslFilterWarningMessage {
    <#
    .SYNOPSIS
        The text of a filter parser warning, with what it means for the mode the filter is attached in.

    .DESCRIPTION
        ConvertFrom-IslFilterRule reports a clause as "never matches" or "matches every device"
        without knowing whether the filter is attached to an assignment in include or exclude mode,
        and the two modes turn the same clause into opposite outcomes: an include filter that never
        matches reaches nobody (W32-FILTER-INCLUDE), while an exclude filter that never matches
        excludes nobody, so the assignment reaches every device in the group (W32-FILTER-EXCLUDE).
        Test-IntuneAssignmentFilter and Test-IntuneDeployedScript know the mode, and append the
        exclude-mode consequence here so one message is read the same way in both places. Include
        mode and the other warning kinds come back unchanged.

    .PARAMETER Warning
        One IntuneScriptLab.FilterWarning from ConvertFrom-IslFilterRule (Kind and Message).

    .PARAMETER Mode
        Include (the default) or Exclude: how the filter is attached to the assignment.

    .EXAMPLE
        Get-IslFilterWarningMessage -Warning $parsed.Warnings[0] -Mode Exclude

        The "never matches" message followed by "; as an exclude filter it excludes nobody, so the
        assignment reaches every device in the group".

    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        $Warning,

        [ValidateSet('Include', 'Exclude')]
        [string]$Mode = 'Include'
    )

    $note = if ($Mode -ne 'Exclude') { '' }
    elseif ($Warning.Kind -eq 'NeverMatches') {
        '; as an exclude filter it excludes nobody, so the assignment reaches every device in the group'
    }
    elseif ($Warning.Kind -eq 'AlwaysMatches') {
        '; as an exclude filter it excludes every device, so the assignment reaches nobody'
    }
    else { '' }
    "$($Warning.Message)$note"
}
