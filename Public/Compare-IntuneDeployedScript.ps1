function Compare-IntuneDeployedScript {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Reports where a tenant's deployed scripts differ from the copies in a folder or repository.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.DriftResult')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,

        [hashtable]$Map,

        [ValidateSet('Remediation', 'PlatformScript', 'Win32App')]
        [string[]]$Kind = @('Remediation', 'PlatformScript', 'Win32App'),

        [SupportsWildcards()]
        [string[]]$Name = @('*'),

        [string[]]$Id,

        $Settings
    )
    Write-Verbose ("Starting $($MyInvocation.MyCommand.Name) against $Path for $($Kind -join ', ') named " +
        "$($Name -join ', ')$(if ($Id) { " or with id $($Id -join ', ')" })")

    try {
        $root = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        $recordSplat = @{
            Message = "Path must be a folder holding the local scripts: $Path"
            ErrorId = 'LocalPathNotFolder'
            Category = [System.Management.Automation.ErrorCategory]::InvalidArgument
            TargetObject = $Path
            ExceptionType = [System.ArgumentException]
        }
        $PSCmdlet.ThrowTerminatingError((New-IslErrorRecord @recordSplat))
    }
    $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.ps1')
    $folders = @(Get-Item -LiteralPath $root) + @(Get-ChildItem -LiteralPath $root -Recurse -Directory)
    $settingsCache = @{}
    $mapped = @{}
    $sha = [System.Security.Cryptography.SHA256]::Create()
    # Which policies of each list to read; -Id alone selects by id, so whether -Name was given counts
    $wanted = @{ Name = $Name; Id = $Id; NameGiven = $PSBoundParameters.ContainsKey('Name') }
    # Captured here: inside the nested functions $PSBoundParameters is their own, not this command's
    $settingsGiven = $PSBoundParameters.ContainsKey('Settings')

    function Get-NameKey {
        param([string]$Value)
        ([regex]::Replace($Value, '[^\w.-]', '_')).ToLowerInvariant()
    }

    function Get-Hash {
        param([byte[]]$Bytes)
        ([System.BitConverter]::ToString($sha.ComputeHash($Bytes)) -replace '-', '').ToLowerInvariant()
    }

    # The -Map entry for a policy, by display name or id; remembers which entries matched
    function Get-MapEntry {
        param($Policy)
        if (-not $Map) { return $null }
        $policyName = "$(Get-IslPropertyValue -InputObject $Policy -Name 'displayName')"
        $policyId = "$(Get-IslPropertyValue -InputObject $Policy -Name 'id')"
        foreach ($key in $Map.Keys) {
            if ("$key" -eq $policyName -or "$key" -eq $policyId) {
                $mapped["$key"] = $true
                return $Map[$key]
            }
        }
        $null
    }

    # The local candidates for one role: the -Map entry when there is one, else the convention.
    # Pattern is matched against the base names inside a folder named after the policy; without a
    # pattern the file named after the policy, or the single script in that folder, is the candidate
    function Find-LocalFile {
        param($Policy, [string]$Role, [string]$Pattern)
        $entry = Get-MapEntry -Policy $Policy
        if ($null -ne $entry) {
            $value = $null
            if ($entry -is [hashtable]) {
                $roleKey = @($entry.Keys | Where-Object { "$_" -eq $Role })
                if ($roleKey.Count) { $value = $entry[$roleKey[0]] }
            }
            elseif ($Role -in 'detection', 'script') { $value = $entry }
            if ($null -eq $value -or "$value" -eq '') { return @() }
            $full = if ([System.IO.Path]::IsPathRooted("$value")) { "$value" }
            else { Join-Path -Path $root -ChildPath "$value" }
            return @([pscustomobject]@{ FullName = $full })
        }
        $key = Get-NameKey -Value "$(Get-IslPropertyValue -InputObject $Policy -Name 'displayName')"
        $named = @($folders | Where-Object { (Get-NameKey -Value $_.Name) -eq $key })
        $inside = @(foreach ($folder in $named) {
                $files | Where-Object { $_.DirectoryName -eq $folder.FullName }
            })
        if ($Pattern) { return @($inside | Where-Object { $_.BaseName -match $Pattern }) }
        $byName = @($files | Where-Object { (Get-NameKey -Value $_.BaseName) -eq $key })
        $single = @(if ($inside.Count -eq 1) { $inside })
        @($byName + $single | Sort-Object -Property FullName -Unique)
    }

    function ConvertTo-Text {
        param([byte[]]$Bytes)
        $bom = $Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF
        $start = if ($bom) { 3 } else { 0 }
        [pscustomobject]@{
            Bom  = $bom
            Text = [System.Text.Encoding]::UTF8.GetString($Bytes, $start, $Bytes.Length - $start)
        }
    }

    function Get-LineEnding {
        param([string]$Text)
        if ($Text -match "`r`n") { 'CRLF' } elseif ($Text -match "`n") { 'LF' } else { '' }
    }

    # The lines without the blank ones at the end
    function Get-TrimmedLine {
        param([string[]]$Lines)
        $count = $Lines.Count
        while ($count -gt 0 -and -not $Lines[$count - 1]) { $count-- }
        if ($count -eq 0) { return @() }
        @($Lines[0..($count - 1)])
    }

    function Get-Excerpt {
        param([string]$Line)
        $trimmed = $Line.Trim()
        if ($trimmed.Length -gt 60) { $trimmed.Substring(0, 57) + '...' } else { $trimmed }
    }

    # What differs between two scripts that are not byte-identical: the BOM, the line-ending style,
    # the content (first differing line and how many lines each side has alone) or only trailing
    # whitespace and blank lines at the end
    function Get-Difference {
        param([byte[]]$Local, [byte[]]$Tenant)
        $differences = [System.Collections.Generic.List[string]]::new()
        $details = [System.Collections.Generic.List[string]]::new()
        $localText = ConvertTo-Text -Bytes $Local
        $tenantText = ConvertTo-Text -Bytes $Tenant
        if ($localText.Bom -ne $tenantText.Bom) {
            $differences.Add('Bom')
            $localBom = if ($localText.Bom) { 'has a BOM' } else { 'has no BOM' }
            $tenantBom = if ($tenantText.Bom) { 'has one' } else { 'has none' }
            $details.Add("the local file $localBom, the tenant's $tenantBom")
        }
        $localEol = Get-LineEnding -Text $localText.Text
        $tenantEol = Get-LineEnding -Text $tenantText.Text
        if ($localEol -and $tenantEol -and $localEol -ne $tenantEol) {
            $differences.Add('LineEndings')
            $details.Add("line endings $localEol locally, $tenantEol in the tenant")
        }
        $localLines = @($localText.Text -split "`r?`n")
        $tenantLines = @($tenantText.Text -split "`r?`n")
        $localTrim = Get-TrimmedLine -Lines @($localLines | ForEach-Object { $_.TrimEnd() })
        $tenantTrim = Get-TrimmedLine -Lines @($tenantLines | ForEach-Object { $_.TrimEnd() })
        if (($localTrim -join "`n") -cne ($tenantTrim -join "`n")) {
            $differences.Add('Content')
            $line = 0
            $limit = [Math]::Min($localTrim.Count, $tenantTrim.Count)
            while ($line -lt $limit -and $localTrim[$line] -ceq $tenantTrim[$line]) { $line++ }
            $localExcerpt = '<end>'
            if ($line -lt $localTrim.Count) { $localExcerpt = Get-Excerpt -Line $localTrim[$line] }
            $tenantExcerpt = '<end>'
            if ($line -lt $tenantTrim.Count) { $tenantExcerpt = Get-Excerpt -Line $tenantTrim[$line] }
            $compareSplat = @{
                ReferenceObject = @($localTrim); DifferenceObject = @($tenantTrim); CaseSensitive = $true
            }
            $compared = @(Compare-Object @compareSplat)
            $onlyLocal = @($compared | Where-Object SideIndicator -eq '<=').Count
            $onlyTenant = @($compared | Where-Object SideIndicator -eq '=>').Count
            $details.Add(("content differs from line $($line + 1): local '$localExcerpt', tenant " +
                    "'$tenantExcerpt' ($onlyLocal line(s) only local, $onlyTenant only in the tenant)"))
        }
        elseif (($localLines -join "`n") -cne ($tenantLines -join "`n")) {
            $differences.Add('Whitespace')
            $details.Add('only trailing whitespace or blank lines at the end differ')
        }
        if ($differences.Count -eq 0) {
            $differences.Add('Content')
            $details.Add('the bytes differ outside the UTF-8 text')
        }
        [pscustomobject]@{ Differences = @($differences); Detail = ($details -join '; ') }
    }

    # The explicit local settings only: a directive in the file, then the settings file
    function Get-LocalSetting {
        param([string]$File)
        $directive = @{}
        $text = [System.IO.File]::ReadAllText($File)
        foreach ($match in [regex]::Matches($text, '(?m)^\s*#\s*IntuneScriptLab\s*:\s*(.+)$')) {
            foreach ($pair in ($match.Groups[1].Value -split '[\s;,]+')) {
                if ($pair -match '^(Context|Architecture|EnforceSignatureCheck)=(\w+)$') {
                    $directive[$Matches[1]] = $Matches[2]
                }
            }
        }
        $settingSplat = @{ Path = $File; Cache = $settingsCache }
        if ($settingsGiven) { $settingSplat.Settings = $Settings }
        $fileSettings = Get-IslSetting @settingSplat
        $explicit = @{}
        foreach ($key in 'Context', 'Architecture', 'EnforceSignatureCheck') {
            if ($directive.ContainsKey($key)) { $explicit[$key] = $directive[$key] }
            elseif ($null -ne $fileSettings.$key -and "$($fileSettings.$key)" -ne '') {
                $explicit[$key] = $fileSettings.$key
            }
        }
        $explicit
    }

    function Compare-Setting {
        param([string]$File, $RunAsAccount, $RunAs32Bit, $EnforceSignatureCheck, [bool]$HasContext)
        $local = Get-LocalSetting -File $File
        $notes = foreach ($key in @($local.Keys)) {
            switch ($key) {
                'Context' {
                    if (-not $HasContext) { continue }
                    $tenantContext = if ("$RunAsAccount" -eq 'user') { 'User' } else { 'System' }
                    if ("$($local.Context)" -ne $tenantContext) {
                        "Context=$($local.Context) locally, the policy runs as $tenantContext"
                    }
                }
                'Architecture' {
                    $tenantArchitecture = if ([bool]$RunAs32Bit) { 'x86' } else { 'x64' }
                    $localArchitecture = if ("$($local.Architecture)" -eq 'x86') { 'x86' } else { 'x64' }
                    if ($localArchitecture -ne $tenantArchitecture) {
                        "Architecture=$($local.Architecture) locally, the policy runs $tenantArchitecture"
                    }
                }
                'EnforceSignatureCheck' {
                    $localFlag = "$($local.EnforceSignatureCheck)" -in 'true', '1', 'yes'
                    if ($localFlag -ne [bool]$EnforceSignatureCheck) {
                        "EnforceSignatureCheck=$localFlag locally, $([bool]$EnforceSignatureCheck) on the policy"
                    }
                }
            }
        }
        @($notes)
    }

    function ConvertTo-Result {
        param(
            [string]$PolicyKind, $Policy, [string]$Role, [string]$State, [string[]]$Differences,
            [string]$Detail, [string]$LocalPath, [string]$LocalHash, [string]$TenantHash
        )
        [pscustomobject]@{
            PSTypeName     = 'IntuneScriptLab.DriftResult'
            Kind           = $PolicyKind
            PolicyName     = "$(Get-IslPropertyValue -InputObject $Policy -Name 'displayName')"
            PolicyId       = "$(Get-IslPropertyValue -InputObject $Policy -Name 'id')"
            Role           = $Role
            State          = $State
            Differences    = @($Differences | Where-Object { $_ })
            Detail         = $Detail
            LocalPath      = $LocalPath
            LocalHash      = $LocalHash
            TenantHash     = $TenantHash
            TenantModified = Get-IslPropertyValue -InputObject $Policy -Name 'lastModifiedDateTime'
        }
    }

    # One role of one policy: the tenant's base64 script against its local candidates
    function Compare-Role {
        param(
            [string]$PolicyKind, $Policy, [string]$Role, [string]$Content, [object[]]$Candidates,
            $RunAsAccount, $RunAs32Bit, $EnforceSignatureCheck, [bool]$HasContext = $true
        )
        $base = @{ PolicyKind = $PolicyKind; Policy = $Policy; Role = $Role }
        $label = if ($Role -eq 'script') { 'script' } else { "$Role script" }
        # An empty candidate list arrives as $null through the splat
        $candidates = @($Candidates | Where-Object { $_ })
        if (-not $Content) {
            if ($candidates.Count -gt 0) {
                ConvertTo-Result @base -State 'NotInTenant' -LocalPath $candidates[0].FullName -Detail (
                    "the policy has no $label; $($candidates[0].FullName) exists locally")
            }
            return
        }
        $tenantBytes = [System.Convert]::FromBase64String($Content)
        $tenantHash = Get-Hash -Bytes $tenantBytes
        $tenantShort = $tenantHash.Substring(0, 12)
        if ($candidates.Count -eq 0) {
            $policyName = Get-IslPropertyValue -InputObject $Policy -Name 'displayName'
            ConvertTo-Result @base -State 'Missing' -TenantHash $tenantShort -Detail (
                "no local file for the $label of '$policyName' under $root")
            return
        }
        if ($candidates.Count -gt 1) {
            $paths = ($candidates | ForEach-Object { $_.FullName }) -join ', '
            ConvertTo-Result @base -State 'Ambiguous' -TenantHash $tenantShort -Detail (
                "$($candidates.Count) local candidates: $paths")
            return
        }
        $file = "$($candidates[0].FullName)"
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
            ConvertTo-Result @base -State 'Missing' -LocalPath $file -TenantHash $tenantShort -Detail (
                "$file does not exist")
            return
        }
        $localBytes = [System.IO.File]::ReadAllBytes($file)
        $localHash = Get-Hash -Bytes $localBytes
        $differences = @()
        $details = @()
        if ($localHash -ne $tenantHash) {
            $difference = Get-Difference -Local $localBytes -Tenant $tenantBytes
            $differences = @($difference.Differences)
            $details = @($difference.Detail)
        }
        $settingSplat = @{
            File = $file; RunAsAccount = $RunAsAccount; RunAs32Bit = $RunAs32Bit
            EnforceSignatureCheck = $EnforceSignatureCheck; HasContext = $HasContext
        }
        $settingNotes = @(Compare-Setting @settingSplat)
        if ($settingNotes.Count) {
            $differences += 'Settings'
            $details += ($settingNotes -join '; ')
        }
        $state = if ($differences.Count) { 'Drifted' } else { 'InSync' }
        $resultSplat = @{
            State = $state; Differences = $differences; Detail = ($details -join '; '); LocalPath = $file
            LocalHash = $localHash.Substring(0, 12); TenantHash = $tenantShort
        }
        ConvertTo-Result @base @resultSplat
    }

    # Several script rules of one app pair with the local files in name order; a lone rule takes
    # every candidate (one is a match, more is ambiguous)
    function Select-Candidate {
        param([object[]]$Files, [int]$RuleCount, [int]$Index)
        $files = @($Files)
        if ($files.Count -eq $RuleCount) { return @($files[$Index]) }
        if ($Index -eq 0) { return $files }
        @()
    }

    try {
        if ('Remediation' -in $Kind) {
            $remediations = '/beta/deviceManagement/deviceHealthScripts'
            try {
                $summaries = @(Get-IslSelectedPolicy -Uri "$remediations`?`$select=id,displayName" @wanted)
            } catch {
                $PSCmdlet.ThrowTerminatingError($_)
            }
            foreach ($summary in $summaries) {
                # A read that fails ends the command. What one policy gives is written after its try, so
                # that an error of a command further down the pipeline is not caught here
                $policyOutput = try {
                    $summaryId = Get-IslPropertyValue -InputObject $summary -Name 'id'
                    $policy = Invoke-IslGraphRequest -Uri "$remediations/$summaryId"
                    $enforceSignature = Get-IslPropertyValue -InputObject $policy -Name 'enforceSignatureCheck'
                    $policySettings = @{
                        RunAsAccount = Get-IslPropertyValue -InputObject $policy -Name 'runAsAccount'
                        RunAs32Bit = Get-IslPropertyValue -InputObject $policy -Name 'runAs32Bit'
                        EnforceSignatureCheck = $enforceSignature
                    }
                    $detectSplat = @{
                        PolicyKind = 'Remediation'
                        Policy = $policy
                        Role = 'detection'
                        Content = Get-IslPropertyValue -InputObject $policy -Name 'detectionScriptContent'
                        Candidates = Find-LocalFile -Policy $policy -Role 'detection' -Pattern '^(?i)detect'
                    }
                    Compare-Role @detectSplat @policySettings
                    $remediateSplat = @{
                        PolicyKind = 'Remediation'
                        Policy = $policy
                        Role = 'remediation'
                        Content = Get-IslPropertyValue -InputObject $policy -Name 'remediationScriptContent'
                        Candidates = Find-LocalFile -Policy $policy -Role 'remediation' -Pattern '^(?i)remediat'
                    }
                    Compare-Role @remediateSplat @policySettings
                } catch {
                    $PSCmdlet.ThrowTerminatingError($_)
                }
                $policyOutput
            }
        }

        if ('PlatformScript' -in $Kind) {
            $scripts = '/beta/deviceManagement/deviceManagementScripts'
            try {
                $summaries = @(Get-IslSelectedPolicy -Uri "$scripts`?`$select=id,displayName" @wanted)
            } catch {
                $PSCmdlet.ThrowTerminatingError($_)
            }
            foreach ($summary in $summaries) {
                $policyOutput = try {
                    $summaryId = Get-IslPropertyValue -InputObject $summary -Name 'id'
                    $policy = Invoke-IslGraphRequest -Uri "$scripts/$summaryId"
                    $enforceSignature = Get-IslPropertyValue -InputObject $policy -Name 'enforceSignatureCheck'
                    $scriptSplat = @{
                        PolicyKind = 'PlatformScript'
                        Policy = $policy
                        Role = 'script'
                        Content = Get-IslPropertyValue -InputObject $policy -Name 'scriptContent'
                        RunAsAccount = Get-IslPropertyValue -InputObject $policy -Name 'runAsAccount'
                        RunAs32Bit = Get-IslPropertyValue -InputObject $policy -Name 'runAs32Bit'
                        EnforceSignatureCheck = $enforceSignature
                        Candidates = Find-LocalFile -Policy $policy -Role 'script'
                    }
                    Compare-Role @scriptSplat
                } catch {
                    $PSCmdlet.ThrowTerminatingError($_)
                }
                $policyOutput
            }
        }

        if ('Win32App' -in $Kind) {
            $apps = '/beta/deviceAppManagement/mobileApps'
            $listUri = "$apps`?`$filter=isof('microsoft.graph.win32LobApp')&`$select=id,displayName"
            try {
                $summaries = @(Get-IslSelectedPolicy -Uri $listUri @wanted)
            } catch {
                $PSCmdlet.ThrowTerminatingError($_)
            }
            foreach ($summary in $summaries) {
                $policyOutput = try {
                    $summaryId = Get-IslPropertyValue -InputObject $summary -Name 'id'
                    $app = Invoke-IslGraphRequest -Uri "$apps/$summaryId"
                    $scriptType = '#microsoft.graph.win32LobAppPowerShellScriptDetection'
                    $detectionRules = @(
                        Get-IslPropertyValue -InputObject $app -Name 'detectionRules' | Where-Object {
                            "$(Get-IslPropertyValue -InputObject $_ -Name '@odata.type')" -eq $scriptType
                        })
                    $detectionFiles = @(Find-LocalFile -Policy $app -Role 'detection' -Pattern '^(?i)detect')
                    for ($index = 0; $index -lt $detectionRules.Count; $index++) {
                        $candidateSplat = @{
                            Files = $detectionFiles; RuleCount = $detectionRules.Count; Index = $index
                        }
                        $candidates = Select-Candidate @candidateSplat
                        $rule = $detectionRules[$index]
                        $signatureCheck = Get-IslPropertyValue -InputObject $rule -Name 'enforceSignatureCheck'
                        $detectSplat = @{
                            PolicyKind = 'Win32App'
                            Policy = $app
                            Role = 'detection'
                            Content = Get-IslPropertyValue -InputObject $rule -Name 'scriptContent'
                            Candidates = $candidates
                            RunAsAccount = 'system'
                            RunAs32Bit = Get-IslPropertyValue -InputObject $rule -Name 'runAs32Bit'
                            EnforceSignatureCheck = $signatureCheck
                            HasContext = $false
                        }
                        Compare-Role @detectSplat
                    }
                    if ($detectionRules.Count -eq 0 -and $detectionFiles.Count -gt 0) {
                        $noRuleSplat = @{
                            PolicyKind = 'Win32App'; Policy = $app; Role = 'detection'; Content = ''
                            Candidates = $detectionFiles
                        }
                        Compare-Role @noRuleSplat
                    }
                    $requirementType = '#microsoft.graph.win32LobAppPowerShellScriptRequirement'
                    $requirementRules = @(
                        Get-IslPropertyValue -InputObject $app -Name 'requirementRules' | Where-Object {
                            "$(Get-IslPropertyValue -InputObject $_ -Name '@odata.type')" -eq $requirementType
                        })
                    $requirementFind = @{ Policy = $app; Role = 'requirement'; Pattern = '^(?i)requirement' }
                    $requirementFiles = @(Find-LocalFile @requirementFind)
                    if ($requirementRules.Count -eq 0) {
                        $noRuleSplat = @{
                            PolicyKind = 'Win32App'; Policy = $app; Role = 'requirement'; Content = ''
                            Candidates = $requirementFiles
                        }
                        Compare-Role @noRuleSplat
                    }
                    for ($index = 0; $index -lt $requirementRules.Count; $index++) {
                        $candidateSplat = @{
                            Files = $requirementFiles; RuleCount = $requirementRules.Count; Index = $index
                        }
                        $candidates = Select-Candidate @candidateSplat
                        $rule = $requirementRules[$index]
                        $signatureCheck = Get-IslPropertyValue -InputObject $rule -Name 'enforceSignatureCheck'
                        $requirementSplat = @{
                            PolicyKind = 'Win32App'
                            Policy = $app
                            Role = 'requirement'
                            Content = Get-IslPropertyValue -InputObject $rule -Name 'scriptContent'
                            Candidates = $candidates
                            RunAsAccount = Get-IslPropertyValue -InputObject $rule -Name 'runAsAccount'
                            RunAs32Bit = Get-IslPropertyValue -InputObject $rule -Name 'runAs32Bit'
                            EnforceSignatureCheck = $signatureCheck
                        }
                        Compare-Role @requirementSplat
                    }
                } catch {
                    $PSCmdlet.ThrowTerminatingError($_)
                }
                $policyOutput
            }
        }

        $unmatched = @(if ($Map) { $Map.Keys | Where-Object { -not $mapped.ContainsKey("$_") } })
        foreach ($key in $unmatched) {
            $entry = $Map[$key]
            $first = if ($entry -is [hashtable]) { @($entry.Values)[0] } else { $entry }
            $orphan = [pscustomobject]@{ displayName = "$key"; id = ''; lastModifiedDateTime = $null }
            $orphanSplat = @{
                PolicyKind = ''; Policy = $orphan; Role = 'policy'; State = 'NotInTenant'; LocalPath = "$first"
                Detail     = "no policy named '$key' among the kinds compared ($($Kind -join ', '))"
            }
            ConvertTo-Result @orphanSplat
        }
    }
    finally {
        $sha.Dispose()
    }
    Write-Verbose "Completed $($MyInvocation.MyCommand.Name)"
}
