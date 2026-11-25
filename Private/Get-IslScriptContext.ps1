function Get-IslScriptContext {
    <#
    .SYNOPSIS
        Parses a script and works out how Intune would run it.

    .DESCRIPTION
        Produces the object every rule receives: the AST and tokens, the raw bytes (for the
        encoding rule), and the effective ScriptType, Context and Architecture. Explicit
        parameters win, then a directive comment inside the script, then the settings file
        (Get-IslSetting), then inference from the file name, then the defaults Intune itself
        applies.

        Directive comment, anywhere in the script:
            # IntuneScriptLab: ScriptType=Detection Context=User Architecture=x86
            # IntuneScriptLab: ScriptType=Win32Detection EnforceSignatureCheck=true

    .PARAMETER Path
        The script file.

    .PARAMETER ScriptType
        Detection, Remediation, PlatformScript, Win32Detection or Win32Requirement. Auto reads
        the directive, the settings, then the file name.

    .PARAMETER Context
        System or User. Auto reads the directive, the settings, then takes the portal's default:
        User for a platform script, System for every other type.

    .PARAMETER Architecture
        The host the script runs in: x86 (SysWOW64), x64 (System32 on an x64 device) or arm64
        (System32 on an ARM64 device, which has no x64 host). Auto reads the directive, the
        settings, then takes the portal's default: x64 for a Win32 detection or requirement
        script, x86 for every other type.

    .PARAMETER EnforceSignatureCheck
        The Win32 rule's "Enforce script signature check". Auto reads the directive, the
        settings, then takes off.

    .PARAMETER Settings
        The IntuneScriptLab.Settings object for the script, from Get-IslSetting. Its entries
        apply when neither a parameter nor a directive sets them.

    .EXAMPLE
        Get-IslScriptContext -Path .\Remediations\Printer\Detect.ps1

        The context of a detection script, its type inferred from the file name.

    .INPUTS
        None.

    .OUTPUTS
        IntuneScriptLab.ScriptContext.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.ScriptContext')]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [ValidateSet('Auto', 'Detection', 'Remediation', 'PlatformScript', 'Win32Detection', 'Win32Requirement')]
        [string]$ScriptType = 'Auto',

        [ValidateSet('Auto', 'System', 'User')]
        [string]$Context = 'Auto',

        # The host the script runs in: x86 (SysWOW64), x64 (System32 on an x64 device) or arm64
        # (System32 on an ARM64 device, native ARM64 PowerShell; there is no x64 host there)
        [ValidateSet('Auto', 'x86', 'x64', 'arm64')]
        [string]$Architecture = 'Auto',

        # The Win32 rule's "Enforce script signature check"; Auto reads the directive, else off
        [ValidateSet('Auto', 'True', 'False')]
        [string]$EnforceSignatureCheck = 'Auto',

        # The IntuneScriptLab.Settings object for the script; its type, context, architecture and
        # signature entries apply when neither a parameter nor a directive sets them
        [pscustomobject]$Settings
    )

    $resolved = (Resolve-Path -LiteralPath $Path).ProviderPath
    $bytes = [System.IO.File]::ReadAllBytes($resolved)
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($resolved, [ref]$tokens, [ref]$errors)

    # Directive comment overrides inference but not explicit parameters
    $directive = @{}
    foreach ($token in $tokens) {
        if ($token.Kind -ne 'Comment') { continue }
        if ($token.Text -match '^#\s*IntuneScriptLab\s*:\s*(.+)$') {
            foreach ($pair in ($Matches[1] -split '[\s;,]+')) {
                if ($pair -match ('^(ScriptType|Context|' +
                        'Architecture|EnforceSignatureCheck)=(\w+)$')) { $directive[$Matches[1]] = $Matches[2] }
            }
        }
    }

    # Words are matched at a boundary so 'prefix-check.ps1' is not a fix and 'undetectable' is
    # not a detection. The nearest two folder names settle the ambiguous case: a detection script
    # under a Win32, apps or packages folder is a Win32 detection rule and one under a
    # remediations folder is a remediation detection. Without a folder hint, a detection named
    # after an app, package or installer is taken as Win32.
    $name = [System.IO.Path]::GetFileNameWithoutExtension($resolved)
    $folderHint = ''
    $folder = Split-Path -Path $resolved -Parent
    for ($depth = 0; $depth -lt 2 -and $folder -and -not $folderHint; $depth++) {
        $leaf = Split-Path -Path $folder -Leaf
        if ($leaf -match '(?i)(^|[^a-z])(win32|apps?|packages?|installers?|intunewin)([^a-z]|$)') {
            $folderHint = 'Win32'
        } elseif ($leaf -match '(?i)(^|[^a-z])(remediations?|healthscripts?|proactive)([^a-z]|$)') {
            $folderHint = 'Remediation'
        }
        $folder = Split-Path -Path $folder -Parent
    }
    $win32Words = '(?i)(^|[^a-z])(app|apps|win32|package|software|install|installed|msi|exe)([^a-z]|$)'
    $inferredSource = 'inferred from file name'
    $inferredType = switch -Regex ($name) {
        '(?i)(^|[^a-z])requirement' { 'Win32Requirement'; break }
        '(?i)(^|[^a-z])detect' {
            if ($folderHint) { $inferredSource = 'inferred from folder and file name' }
            if ($folderHint -eq 'Win32') { 'Win32Detection' }
            elseif ($folderHint -eq 'Remediation') { 'Detection' }
            elseif ($name -match $win32Words) { 'Win32Detection' }
            else { 'Detection' }
            break
        }
        '(?i)(^|[^a-z])(remediat\w*|fix)([^a-z]|$)' { 'Remediation'; break }
        default { 'PlatformScript' }
    }
    # -Settings is optional, and a directive names only some of the four keys. An index reads a
    # key the directive lacks as $null, and the accessor does the same for the settings object
    $settingsType = Get-IslPropertyValue -InputObject $Settings -Name 'ScriptType'
    $settingsContext = Get-IslPropertyValue -InputObject $Settings -Name 'Context'
    $settingsArchitecture = Get-IslPropertyValue -InputObject $Settings -Name 'Architecture'
    $settingsSignatureCheck = Get-IslPropertyValue -InputObject $Settings -Name 'EnforceSignatureCheck'

    $typeSource = 'parameter'
    $resolvedType = $ScriptType
    if ($ScriptType -eq 'Auto') {
        if ($directive['ScriptType']) { $resolvedType = $directive['ScriptType']; $typeSource = 'directive' }
        elseif ($settingsType) { $resolvedType = $settingsType; $typeSource = 'settings' }
        else { $resolvedType = $inferredType; $typeSource = $inferredSource }
    }

    # Intune's own defaults when nothing says otherwise. Portal defaults differ from API defaults
    # (Findings.md, "Graph API defaults"); these are the portal ones because that is what most
    # scripts get, and they are the more restrictive assumption for the rules.
    $resolvedContext = $Context
    if ($Context -eq 'Auto') {
        $resolvedContext = if ($directive['Context']) { $directive['Context'] }
        elseif ($settingsContext) { $settingsContext }
        elseif ($resolvedType -eq 'PlatformScript') { 'User' }   # portal default for platform scripts
        else { 'System' }
    }
    $resolvedArchitecture = $Architecture
    if ($Architecture -eq 'Auto') {
        $resolvedArchitecture = if ($directive['Architecture']) { $directive['Architecture'] }
        elseif ($settingsArchitecture) { $settingsArchitecture }
        elseif ($resolvedType -in 'Win32Detection', 'Win32Requirement') { 'x64' }  # 64-bit by default
        else { 'x86' }                                                            # scripts/remediations: 32-bit
    }

    $signatureCheck = if ($EnforceSignatureCheck -ne 'Auto') { $EnforceSignatureCheck -eq 'True' }
    elseif ($directive.ContainsKey('EnforceSignatureCheck')) {
        "$($directive['EnforceSignatureCheck'])" -in 'true', '1', 'yes'
    } elseif ($null -ne $settingsSignatureCheck) { [bool]$settingsSignatureCheck }
    else { $false }

    [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.ScriptContext'
        Path = $resolved
        Ast = $ast
        Tokens = $tokens
        ParseErrors = @($errors)
        Bytes = $bytes
        ScriptType = $resolvedType
        TypeSource = $typeSource
        Context = $resolvedContext
        Architecture = $resolvedArchitecture
        EnforceSignatureCheck = $signatureCheck
    }
}
