function Compare-IslPolicyScript {
    <#
    .SYNOPSIS
    Compares one script of a tenant policy with its local candidates.

    .DESCRIPTION
    For Compare-IntuneDeployedScript. The tenant's script, base64 as Graph stores it, is compared
    with the local candidates Find-IslLocalScript found, and one IntuneScriptLab.DriftResult is
    written for the role:

    - NotInTenant: the policy has no such script, and a local file exists for it. A policy
      without the script and without a local file gives nothing.
    - Missing: no local candidate, or the one named does not exist.
    - Ambiguous: more than one local candidate.
    - InSync or Drifted: one local file, compared byte for byte by its SHA-256 hash. A file whose
      bytes differ is described by Get-IslScriptDifference, and run settings the file states for
      itself that differ from the policy's (Compare-IslScriptSetting) are a Settings difference.

    A file or setting that cannot be read ends the function with the error.

    .PARAMETER PolicyKind
    Remediation, PlatformScript or Win32App.

    .PARAMETER Policy
    The policy as Graph returns it.

    .PARAMETER Role
    The script's role: detection, remediation, script or requirement.

    .PARAMETER Content
    The tenant's script, base64 encoded. Nothing means the policy has no such script.

    .PARAMETER Candidates
    The local candidates, each an object with FullName.

    .PARAMETER RunAsAccount
    The account the script runs as.

    .PARAMETER RunAs32Bit
    Whether the script runs in the 32-bit host.

    .PARAMETER EnforceSignatureCheck
    Whether the script's signature is checked.

    .PARAMETER SkipContext
    Leaves the run context out of the settings comparison, for a Win32 app's detection script.

    .PARAMETER Root
    The full path of the caller's -Path, named when no local file is found.

    .PARAMETER SettingsCache
    The settings files already read, by folder.

    .PARAMETER Settings
    The caller's -Settings. Leave it out when the caller gave none.

    .EXAMPLE
    Compare-IslPolicyScript @detectSplat @compareOptions
    # $detectSplat holds PolicyKind, Policy, Role, Content and Candidates

    InSync when the remediation's detection script matches its local copy byte for byte.

    .INPUTS
    None.

    .OUTPUTS
    IntuneScriptLab.DriftResult.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.DriftResult')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Remediation', 'PlatformScript', 'Win32App')]
        [string]$PolicyKind,

        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Policy,

        [Parameter(Mandatory)]
        [string]$Role,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Content,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Candidates,

        [Parameter()]
        [AllowNull()]
        [object]$RunAsAccount,

        [Parameter()]
        [AllowNull()]
        [object]$RunAs32Bit,

        [Parameter()]
        [AllowNull()]
        [object]$EnforceSignatureCheck,

        [Parameter()]
        [switch]$SkipContext,

        [Parameter(Mandatory)]
        [string]$Root,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [hashtable]$SettingsCache,

        [Parameter()]
        [object]$Settings
    )

    $base = @{ PolicyKind = $PolicyKind; Policy = $Policy; Role = $Role }
    $label = if ($Role -eq 'script') { 'script' } else { "$Role script" }
    # An empty candidate list arrives as $null through a splat
    $localFiles = @($Candidates | Where-Object { $_ })
    if (-not $Content) {
        if ($localFiles.Count -gt 0) {
            $existing = $localFiles[0].FullName
            ConvertTo-IslDriftResult @base -State 'NotInTenant' -LocalPath $existing -Detail (
                "the policy has no $label; $existing exists locally")
        }
        return
    }
    try {
        $tenantBytes = [System.Convert]::FromBase64String($Content)
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
    $tenantHash = Get-IslContentHash -Bytes $tenantBytes
    $tenantShort = $tenantHash.Substring(0, 12)
    if ($localFiles.Count -eq 0) {
        $policyName = Get-IslPropertyValue -InputObject $Policy -Name 'displayName'
        ConvertTo-IslDriftResult @base -State 'Missing' -TenantHash $tenantShort -Detail (
            "no local file for the $label of '$policyName' under $Root")
        return
    }
    if ($localFiles.Count -gt 1) {
        $paths = ($localFiles | ForEach-Object { $_.FullName }) -join ', '
        ConvertTo-IslDriftResult @base -State 'Ambiguous' -TenantHash $tenantShort -Detail (
            "$($localFiles.Count) local candidates: $paths")
        return
    }
    $file = "$($localFiles[0].FullName)"
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        ConvertTo-IslDriftResult @base -State 'Missing' -LocalPath $file -TenantHash $tenantShort -Detail (
            "$file does not exist")
        return
    }
    $settingSplat = @{
        File = $file; RunAsAccount = $RunAsAccount; RunAs32Bit = $RunAs32Bit
        EnforceSignatureCheck = $EnforceSignatureCheck; SkipContext = $SkipContext; Cache = $SettingsCache
    }
    if ($PSBoundParameters.ContainsKey('Settings')) { $settingSplat.Settings = $Settings }
    try {
        $localBytes = [System.IO.File]::ReadAllBytes($file)
        $settingNotes = @(Compare-IslScriptSetting @settingSplat)
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
    $localHash = Get-IslContentHash -Bytes $localBytes
    $differences = [System.Collections.Generic.List[string]]::new()
    $details = [System.Collections.Generic.List[string]]::new()
    if ($localHash -ne $tenantHash) {
        $difference = Get-IslScriptDifference -Local $localBytes -Tenant $tenantBytes
        foreach ($name in $difference.Differences) { $differences.Add($name) }
        $details.Add($difference.Detail)
    }
    if ($settingNotes.Count) {
        $differences.Add('Settings')
        $details.Add($settingNotes -join '; ')
    }
    $state = if ($differences.Count) { 'Drifted' } else { 'InSync' }
    $resultSplat = @{
        State = $state; Differences = $differences.ToArray(); Detail = ($details -join '; '); LocalPath = $file
        LocalHash = $localHash.Substring(0, 12); TenantHash = $tenantShort
    }
    ConvertTo-IslDriftResult @base @resultSplat
}
