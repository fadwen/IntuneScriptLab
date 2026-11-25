function ConvertTo-IslDeploymentFinding {
    <#
    .SYNOPSIS
    Turns a finding about a deployed script into one that names its tenant policy.

    .DESCRIPTION
    For Test-IntuneDeployedScript. Adds to a finding of Test-IntuneScript, or to a finding about
    the policy itself, the policy's kind, name and id and the role of the script in the policy,
    so that the caller can tell which policy and which of its scripts the finding is about.

    .PARAMETER PolicyKind
    Remediation, PlatformScript or Win32App.

    .PARAMETER Policy
    The policy as Graph returns it, a dictionary or an object with displayName and id.

    .PARAMETER Role
    Which script of the policy the finding is about, such as detection, remediation, script,
    requirement, or policy for a finding about the policy itself.

    .PARAMETER Finding
    The finding, with RuleName, Severity, Message, ScriptType, Line, Column, Text and Evidence.

    .EXAMPLE
    ConvertTo-IslDeploymentFinding -PolicyKind Remediation -Policy $policy -Role detection -Finding $finding

    The finding with the remediation's name and id and the role detection.

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
        [string]$Role,

        [Parameter(Mandatory)]
        [psobject]$Finding
    )

    [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.DeploymentFinding'
        Kind = $PolicyKind
        PolicyName = "$(Get-IslPropertyValue -InputObject $Policy -Name 'displayName')"
        PolicyId = "$(Get-IslPropertyValue -InputObject $Policy -Name 'id')"
        Role = $Role
        RuleName = $Finding.RuleName
        Severity = $Finding.Severity
        Message = $Finding.Message
        ScriptType = $Finding.ScriptType
        Line = $Finding.Line
        Column = $Finding.Column
        Text = $Finding.Text
        Evidence = $Finding.Evidence
    }
}
