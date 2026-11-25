function Test-IslAssignmentFilter {
    <#
    .SYNOPSIS
    Checks the assignment filters on a tenant policy's assignments.

    .DESCRIPTION
    For Test-IntuneDeployedScript. For each assignment that carries a filter (one without a
    filter carries neither filter key, or the filter type none), the filter is read through
    Get-IslAssignmentFilter and its rule parsed with ConvertFrom-IslFilterRule. A rule this
    evaluator cannot read is an Information finding that names the reason. A clause that no
    Windows device can match is a Warning, because the assignment then silently reaches nobody,
    or everybody when the filter excludes; the parser's other warnings are Information. Each
    finding is an IslFilterIssue built by ConvertTo-IslPolicyFinding, so the caller's rule
    selection and minimum severity apply.

    .PARAMETER PolicyKind
    Remediation, PlatformScript or Win32App.

    .PARAMETER Policy
    The policy as Graph returns it with $expand=assignments.

    .PARAMETER FilterState
    The state Get-IslAssignmentFilter keeps across the run: Cache and Blocked.

    .PARAMETER IncludeRule
    The caller's -IncludeRule patterns.

    .PARAMETER ExcludeRule
    The caller's -ExcludeRule patterns.

    .PARAMETER MinimumSeverity
    The lowest severity the caller wants, Information by default.

    .EXAMPLE
    Test-IslAssignmentFilter -PolicyKind 'Remediation' -Policy $policy -FilterState $filterState

    A Warning for an assignment filtered on (device.cpuArchitecture -eq "x64"), which no Windows
    device reports.

    .INPUTS
    None.

    .OUTPUTS
    IntuneScriptLab.DeploymentFinding.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.DeploymentFinding')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Remediation', 'PlatformScript', 'Win32App')]
        [string]$PolicyKind,

        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Policy,

        [Parameter(Mandatory)]
        [hashtable]$FilterState,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$IncludeRule,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$ExcludeRule,

        [Parameter()]
        [ValidateSet('Information', 'Warning', 'Error')]
        [string]$MinimumSeverity = 'Information'
    )

    $findingSplat = @{
        PolicyKind = $PolicyKind
        Policy = $Policy
        Rule = 'IslFilterIssue'
        IncludeRule = $IncludeRule
        ExcludeRule = $ExcludeRule
        MinimumSeverity = $MinimumSeverity
        Evidence = ('validateFilter accepted (device.cpuArchitecture -eq "x64") and (device.deviceTrustType ' +
            '-eq "Microsoft Entra joined") and the filter evaluator matched no device with either: Windows ' +
            'reports amd64 and "Azure AD joined" (FLT-V25, FLT-E07, FLT-V27, FLT-F01)')
    }
    foreach ($assignment in @(Get-IslPropertyValue -InputObject $Policy -Name 'assignments')) {
        $target = Get-IslPropertyValue -InputObject $assignment -Name 'target'
        $filterId = Get-IslPropertyValue -InputObject $target -Name 'deviceAndAppManagementAssignmentFilterId'
        $filterTypeName = 'deviceAndAppManagementAssignmentFilterType'
        $filterType = "$(Get-IslPropertyValue -InputObject $target -Name $filterTypeName)"
        if (-not $filterId -or $filterType -eq 'none') { continue }
        $filter = Get-IslAssignmentFilter -FilterId $filterId -State $FilterState
        if (-not $filter) { continue }
        $filterRule = "$(Get-IslPropertyValue -InputObject $filter -Name 'rule')"
        $label = "Filter '$(Get-IslPropertyValue -InputObject $filter -Name 'displayName')' ($filterType)"
        $parsed = ConvertFrom-IslFilterRule -Rule $filterRule
        if ($parsed.Error) {
            $message = "$label uses syntax this evaluator does not read ($($parsed.Error)): $filterRule"
            ConvertTo-IslPolicyFinding @findingSplat -Severity 'Information' -Message $message
            continue
        }
        $mode = if ($filterType -eq 'exclude') { 'Exclude' } else { 'Include' }
        foreach ($warning in $parsed.Warnings) {
            $severity = if ($warning.Kind -eq 'NeverMatches') { 'Warning' } else { 'Information' }
            $warningText = Get-IslFilterWarningMessage -Warning $warning -Mode $mode
            $message = "${label}: $warningText. Rule: $filterRule"
            ConvertTo-IslPolicyFinding @findingSplat -Severity $severity -Message $message
        }
    }
}
