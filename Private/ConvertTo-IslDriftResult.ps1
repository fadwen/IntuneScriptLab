function ConvertTo-IslDriftResult {
    <#
    .SYNOPSIS
    Builds the result of comparing one script of a tenant policy with its local copy.

    .DESCRIPTION
    For Compare-IntuneDeployedScript. The result names the policy's kind, name and id and the
    script's role, and carries the state of the comparison with what differs, the local path and
    the short hashes of both sides. The policy's lastModifiedDateTime is TenantModified. Empty
    entries of -Differences are left out.

    .PARAMETER PolicyKind
    Remediation, PlatformScript or Win32App, or nothing for a -Map entry that matched no policy.

    .PARAMETER Policy
    The policy as Graph returns it, or an object with the -Map key as its displayName.

    .PARAMETER Role
    The script's role, or policy for a -Map entry that matched no policy.

    .PARAMETER State
    InSync, Drifted, Missing, Ambiguous or NotInTenant.

    .PARAMETER Differences
    What differs: Bom, LineEndings, Content, Whitespace or Settings.

    .PARAMETER Detail
    The differences described in words.

    .PARAMETER LocalPath
    The local file compared, or the one that has no counterpart in the tenant.

    .PARAMETER LocalHash
    The start of the local file's SHA-256 hash.

    .PARAMETER TenantHash
    The start of the tenant script's SHA-256 hash.

    .EXAMPLE
    ConvertTo-IslDriftResult -PolicyKind 'PlatformScript' -Policy $policy -Role 'script' -State 'InSync'

    The result for a platform script whose local copy is the same.

    .INPUTS
    None.

    .OUTPUTS
    IntuneScriptLab.DriftResult.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.DriftResult')]
    param(
        [Parameter()]
        [ValidateSet('', 'Remediation', 'PlatformScript', 'Win32App')]
        [string]$PolicyKind = '',

        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Policy,

        [Parameter(Mandatory)]
        [string]$Role,

        [Parameter(Mandatory)]
        [ValidateSet('InSync', 'Drifted', 'Missing', 'Ambiguous', 'NotInTenant')]
        [string]$State,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$Differences = @(),

        [Parameter()]
        [string]$Detail = '',

        [Parameter()]
        [string]$LocalPath = '',

        [Parameter()]
        [string]$LocalHash = '',

        [Parameter()]
        [string]$TenantHash = ''
    )

    [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.DriftResult'
        Kind = $PolicyKind
        PolicyName = "$(Get-IslPropertyValue -InputObject $Policy -Name 'displayName')"
        PolicyId = "$(Get-IslPropertyValue -InputObject $Policy -Name 'id')"
        Role = $Role
        State = $State
        Differences = @($Differences | Where-Object { $_ })
        Detail = $Detail
        LocalPath = $LocalPath
        LocalHash = $LocalHash
        TenantHash = $TenantHash
        TenantModified = Get-IslPropertyValue -InputObject $Policy -Name 'lastModifiedDateTime'
    }
}
