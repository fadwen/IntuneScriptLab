function ConvertTo-IslPolicyFinding {
    <#
    .SYNOPSIS
    Builds a finding about a tenant policy itself, when the caller's rule selection keeps it.

    .DESCRIPTION
    For Test-IntuneDeployedScript, for what it finds in a policy's settings and assignments
    rather than in its scripts: a missing remediation script, an assignment that reaches nobody,
    a run-once schedule that has passed, an assignment filter that never matches. The finding is
    written as an IntuneScriptLab.DeploymentFinding with the role policy, unless the rule is left
    out by -IncludeRule or -ExcludeRule (Test-IslRuleSelected) or the severity is below
    -MinimumSeverity, in which case nothing is written.

    .PARAMETER PolicyKind
    Remediation, PlatformScript or Win32App.

    .PARAMETER Policy
    The policy as Graph returns it.

    .PARAMETER Rule
    The finding's rule name, such as IslAssignmentIssue.

    .PARAMETER Severity
    Information, Warning or Error.

    .PARAMETER Message
    What is wrong with the policy.

    .PARAMETER Evidence
    The observation behind the finding, ending in its experiment ids.

    .PARAMETER IncludeRule
    The caller's -IncludeRule patterns. Nothing keeps every rule.

    .PARAMETER ExcludeRule
    The caller's -ExcludeRule patterns.

    .PARAMETER MinimumSeverity
    The lowest severity the caller wants, Information by default.

    .EXAMPLE
    ConvertTo-IslPolicyFinding -PolicyKind 'Remediation' -Policy $policy @detectOnly -ExcludeRule 'IslDetect*'
    # $detectOnly holds the Rule IslDetectOnly, its Severity, Message and Evidence

    Nothing, because -ExcludeRule leaves the rule out; without it, the finding with the role policy.

    .INPUTS
    None.

    .OUTPUTS
    IntuneScriptLab.DeploymentFinding, or nothing.
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
        [string]$Rule,

        [Parameter(Mandatory)]
        [ValidateSet('Information', 'Warning', 'Error')]
        [string]$Severity,

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory)]
        [string]$Evidence,

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

    $severityRank = @{ Information = 0; Warning = 1; Error = 2 }
    $selected = Test-IslRuleSelected -RuleName $Rule -Include $IncludeRule -Exclude $ExcludeRule
    if (-not $selected -or $severityRank[$Severity] -lt $severityRank[$MinimumSeverity]) { return }
    $finding = [pscustomobject]@{
        RuleName = $Rule; Severity = $Severity; Message = $Message; ScriptType = ''
        Line = 0; Column = 0; Text = ''; Evidence = $Evidence
    }
    ConvertTo-IslDeploymentFinding -PolicyKind $PolicyKind -Policy $Policy -Role 'policy' -Finding $finding
}
