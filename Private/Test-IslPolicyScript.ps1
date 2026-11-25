function Test-IslPolicyScript {
    <#
    .SYNOPSIS
    Analyzes one script of a tenant policy with the settings the policy carries.

    .DESCRIPTION
    For Test-IntuneDeployedScript. The script, base64 as Graph stores it, is written byte for byte
    into the work folder, so that the encoding rule sees its byte order mark, or its absence, as
    the tenant stores it. Test-IntuneScript then analyzes it as the script type given, in the
    context and architecture the policy runs it with: User when the policy runs as the user and
    System otherwise, x86 when it runs in the 32-bit host and x64 otherwise, and with the
    policy's signature check. The caller's rule selection, minimum severity and settings apply.

    Each finding is written as an IntuneScriptLab.DeploymentFinding. A policy without that script
    gives nothing. A script that cannot be analyzed ends the function with the error, because a
    policy without findings would read as a policy without problems. The work folder is the
    caller's own and is left in place; the caller removes it.

    .PARAMETER PolicyKind
    Remediation, PlatformScript or Win32App.

    .PARAMETER Policy
    The policy as Graph returns it, with displayName and id.

    .PARAMETER Role
    The script's role in the policy, such as detection, remediation, script or requirement. It
    names the file in the work folder.

    .PARAMETER Content
    The script, base64 encoded. Nothing gives nothing.

    .PARAMETER ScriptType
    The script type for Test-IntuneScript, such as Detection or Win32Requirement.

    .PARAMETER RunAsAccount
    The policy's runAsAccount, system or user.

    .PARAMETER RunAs32Bit
    The policy's runAs32Bit.

    .PARAMETER EnforceSignatureCheck
    The policy's enforceSignatureCheck.

    .PARAMETER WorkFolder
    The folder the scripts are written to, one subfolder for each policy.

    .PARAMETER IncludeRule
    The caller's -IncludeRule patterns.

    .PARAMETER ExcludeRule
    The caller's -ExcludeRule patterns.

    .PARAMETER MinimumSeverity
    The lowest severity the caller wants, Information by default.

    .PARAMETER Settings
    The caller's -Settings, a settings file path or hashtable. Leave it out when the caller gave
    none.

    .EXAMPLE
    Test-IslPolicyScript @detectSplat -WorkFolder $workFolder
    # $detectSplat holds PolicyKind, Policy, Role, Content, ScriptType and the run settings

    The findings of the remediation's detection script, each naming the policy.

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

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Content,

        [Parameter(Mandatory)]
        [string]$ScriptType,

        [Parameter()]
        [AllowNull()]
        [object]$RunAsAccount,

        [Parameter()]
        [AllowNull()]
        [object]$RunAs32Bit,

        [Parameter()]
        [AllowNull()]
        [object]$EnforceSignatureCheck,

        [Parameter(Mandatory)]
        [string]$WorkFolder,

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
        [string]$MinimumSeverity = 'Information',

        [Parameter()]
        [object]$Settings
    )

    if (-not $Content) { return }
    $policyName = "$(Get-IslPropertyValue -InputObject $Policy -Name 'displayName')"
    $policyId = "$(Get-IslPropertyValue -InputObject $Policy -Name 'id')"
    $context = if ("$RunAsAccount" -eq 'user') { 'User' } else { 'System' }
    $architecture = if ([bool]$RunAs32Bit) { 'x86' } else { 'x64' }
    try {
        # The folder is named after the policy, which comes from the tenant (SEC-12, SEC-17). The
        # display name keeps only the characters a folder name can hold, so that it stays
        # readable. The id is refused unless it holds only letters, digits, '-' and '_', as every
        # Graph id, a GUID, does. And the resolved path must stay inside the work folder, whatever
        # the name and the id were
        # \A and \z, not ^ and $: $ also matches before a final line feed, which would let one through
        if ($policyId -notmatch '\A[\w-]+\z') {
            $recordSplat = @{
                Message = "$PolicyKind '$policyName' has an id that cannot name a folder; it was not written"
                ErrorId = 'PolicyIdInvalid'
                Category = 'InvalidData'
                TargetObject = $policyId
            }
            $PSCmdlet.ThrowTerminatingError((New-IslErrorRecord @recordSplat))
        }
        $safeName = [regex]::Replace($policyName, '[^\w.-]', '_')
        $kindFolder = Join-Path -Path $WorkFolder -ChildPath $PolicyKind
        $folder = Join-Path -Path $kindFolder -ChildPath "$safeName-$policyId"
        $file = Join-Path -Path $folder -ChildPath "$Role.ps1"
        $separators = [char[]]@(
            [System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        $workRoot = [System.IO.Path]::GetFullPath($WorkFolder).TrimEnd($separators) +
        [System.IO.Path]::DirectorySeparatorChar
        $fullFile = [System.IO.Path]::GetFullPath($file)
        # Windows compares paths without regard to case; a file system with '/' does not
        $comparison = if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
            [System.StringComparison]::OrdinalIgnoreCase
        } else {
            [System.StringComparison]::Ordinal
        }
        if (-not $fullFile.StartsWith($workRoot, $comparison)) {
            $recordSplat = @{
                Message = "$PolicyKind '$policyName' would be written outside the work folder; it was not written"
                ErrorId = 'PolicyPathOutsideWorkFolder'
                Category = 'SecurityError'
                TargetObject = $policyId
            }
            $PSCmdlet.ThrowTerminatingError((New-IslErrorRecord @recordSplat))
        }
        $null = New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop @script:IslInternal
        [System.IO.File]::WriteAllBytes($file, [System.Convert]::FromBase64String($Content))
        $testSplat = @{
            Path = $file
            ScriptType = $ScriptType
            Context = $context
            Architecture = $architecture
            EnforceSignatureCheck = [bool]$EnforceSignatureCheck
            MinimumSeverity = $MinimumSeverity
            # The analysis reports a script it cannot read and goes on. Here that would leave a
            # policy without findings, which reads as a policy without problems
            ErrorAction = 'Stop'
        }
        if ($PSBoundParameters.ContainsKey('Settings')) { $testSplat.Settings = $Settings }
        if ($IncludeRule) { $testSplat.IncludeRule = $IncludeRule }
        if ($ExcludeRule) { $testSplat.ExcludeRule = $ExcludeRule }
        Write-Verbose "$PolicyKind '$policyName' $Role as $ScriptType, $context, $architecture"
        $findings = @(Test-IntuneScript @testSplat)
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
    foreach ($finding in $findings) {
        ConvertTo-IslDeploymentFinding -PolicyKind $PolicyKind -Policy $Policy -Role $Role -Finding $finding
    }
}
