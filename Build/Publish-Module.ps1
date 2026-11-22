#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Microsoft.PowerShell.PSResourceGet'; ModuleVersion = '1.0.0' }

<#
.SYNOPSIS
    Stages the shipping files into a clean folder and publishes them to a PSResource
    repository.

.DESCRIPTION
    Publish-PSResource packages the whole directory that contains the manifest. This
    repository IS the module root, so publishing from here directly would ship the entire
    working tree - the tests, the validation kit with its tenant-derived findings, the docs
    source, Build, .github, the installed standards, and every object under .git.

    That matters more than package size. A Gallery version can never be deleted, only
    unlisted, and the .nupkg stays downloadable at its direct URL after unlisting. Anything
    published once is published permanently, including a full copy of the repository
    history.

    So the shipping set below is an allowlist, not an exclusion list. A new folder added to
    the repository does not ship until someone names it here deliberately, which is the safe
    direction for that mistake to fail in.

    Examples IS shipped: the README points an installed user at the CI gate script, the
    workflow template, the settings file and the Pester suite template in it, and none of
    them is reachable from the Gallery otherwise. PSScriptAnalyzer IS shipped: it holds the
    rules module Get-IntuneAnalyzerRulePath returns.

    Before staging, Build-Help.ps1 validates the help Markdown under docs/ and rebuilds
    en-US/IntuneScriptLab-Help.xml, which is the help every exported command serves.

.PARAMETER ApiKey
    PowerShell Gallery API key, from https://www.powershellgallery.com/account/apikeys.
    Usually omitted - see -SecretName. Required only if neither the secret vault nor
    $env:PSGALLERY_API_KEY holds a key, and never needed with -WhatIf.

.PARAMETER SecretName
    Name of the SecretManagement secret holding the Gallery API key. Defaults to
    'PSGallery-ApiKey'. Store it once with:

        Set-Secret -Name PSGallery-ApiKey -Secret '<key>'

.PARAMETER VaultName
    The SecretManagement vault that holds the secret. Left out, the default vault is read,
    the one Get-SecretVault reports as IsDefault. No other vault is searched.

.PARAMETER Repository
    Target repository name. Defaults to PSGallery.

.PARAMETER StagingPath
    Where to assemble the shipping tree. Defaults to out/ in the repository root, which is
    git-ignored. Removed and recreated on every run.

.PARAMETER ModuleRoot
    Repository root. Defaults to the parent of the folder holding this script.

.PARAMETER SkipHelpBuild
    Skip the help gates. Only for iterating on this script itself - the committed MAML is
    what users are served, and .EXTERNALHELP means stale help is shown in preference to
    anything correct.

.EXAMPLE
    ./Build/Publish-Module.ps1 -WhatIf

    DESCRIPTION: Stages the shipping tree and reports exactly what would be published
    OUTPUT: The staged file list, total size, and the resolved version
    USE CASE: The rehearsal to run before every real publish

.EXAMPLE
    ./Build/Publish-Module.ps1

    DESCRIPTION: Stages, verifies the staged tree imports in a fresh process, and publishes,
                 taking the API key from the secret vault
    OUTPUT: A confirmation naming the published version
    USE CASE: The actual release, after the tests pass and CHANGELOG.md is updated

.EXAMPLE
    ./Build/Publish-Module.ps1 -Repository LocalTest -ApiKey ignored

    DESCRIPTION: Publishes to a local file-system repository registered with
                 Register-PSResourceRepository
    OUTPUT: A .nupkg in the local repository folder
    USE CASE: Inspecting the real package contents without consuming a Gallery version

.INPUTS
    None.

.OUTPUTS
    None. Progress is written to the information stream, and a failure is a terminating error.

.NOTES
    Author: Jeffrey Stuhr
    Blog: https://www.techbyjeff.net
    LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [string]$ApiKey,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SecretName = 'PSGallery-ApiKey',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$VaultName,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Repository = 'PSGallery',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$StagingPath,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ModuleRoot = (Split-Path -Parent $PSScriptRoot),

    [Parameter()]
    [switch]$SkipHelpBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'


function Get-VaultApiKey {
    <#
    .SYNOPSIS
    Gets the Gallery API key from a SecretManagement vault as a SecureString.

    .DESCRIPTION
    Reads one secret from one named vault. When no vault is named, the default vault is read
    and no other. The secret is returned as a SecureString and is never converted to text
    here. A secret that is missing, a vault that cannot be read, and a missing default vault
    each write a warning and return nothing, so that the caller can report every way a key
    can be supplied.

    .PARAMETER SecretName
    Name of the secret that holds the API key.

    .PARAMETER VaultName
    Name of the vault to read. Left out, the vault that Get-SecretVault reports as the
    default is read.

    .EXAMPLE
    $key = Get-VaultApiKey -SecretName 'PSGallery-ApiKey'

    Reads the key from the default vault. $key is $null when the vault has no such secret.

    .INPUTS
    None.

    .OUTPUTS
    System.Security.SecureString. The API key, or nothing when it could not be read.
    #>
    [CmdletBinding()]
    [OutputType([securestring])]
    param(
        [Parameter(Mandatory)]
        [string]$SecretName,

        [Parameter()]
        [string]$VaultName
    )

    $vault = $VaultName
    if (-not $vault) {
        $defaultVaults = @(Get-SecretVault | Where-Object -Property IsDefault -EQ -Value $true)
        if ($defaultVaults.Count -eq 0) {
            Write-Warning 'No default secret vault is registered. Name the vault with -VaultName.'
            return
        }
        $vault = $defaultVaults[0].Name
    }

    # try/catch, not -ErrorAction SilentlyContinue. A locked SecretStore throws from the vault
    # extension and SilentlyContinue does not suppress it.
    try {
        $secret = Get-Secret -Name $SecretName -Vault $vault -ErrorAction Stop
    } catch {
        Write-Warning ("The secret '$SecretName' could not be read from the vault '$vault': " +
            "$($_.Exception.Message) If the key is stored there, run Unlock-SecretStore and try again.")
        return
    }

    if ($secret -is [System.Management.Automation.PSCredential]) {
        return $secret.Password
    }
    if ($secret -isnot [securestring]) {
        Write-Warning ("The secret '$SecretName' in the vault '$vault' is not text. Store the key with " +
            "Set-Secret -Name $SecretName -Secret '<key>'.")
        return
    }

    $secret
}


$moduleName = 'IntuneScriptLab'

# The complete shipping set. Anything not named here stays out of the package.
$shipFiles = @(
    "$moduleName.psd1"
    "$moduleName.psm1"
    "$moduleName.Format.ps1xml"
    'LICENSE'
    'README.md'
    'CHANGELOG.md'
)
$shipFolders = @(
    'Private'
    'Public'
    'PSScriptAnalyzer'
    'Examples'
    'en-US'
)

if (-not $StagingPath) {
    $StagingPath = Join-Path $ModuleRoot 'out'
}

# --- 0. Resolve the API key -------------------------------------------------------
# Resolved first, so a missing key costs a second rather than failing after the PlatyPS
# help build and the whole staging pass. Skipped under -WhatIf, which publishes nothing.
#
# The key is never stored in this repository, and is kept off the command line where
# possible: the environment variable first (what the release workflow sets), then the
# SecretManagement vault, then the parameter as the override.
#
# A key that arrives as text, from the parameter or the environment variable, stays in
# $plainApiKey. A key from the vault stays a SecureString in $vaultApiKey until the publish
# call converts it for that one call.
$plainApiKey = $ApiKey
$vaultApiKey = $null
if (-not $WhatIfPreference -and -not $plainApiKey) {
    if ($env:PSGALLERY_API_KEY) {
        $plainApiKey = $env:PSGALLERY_API_KEY
        Write-Information 'API key: $env:PSGALLERY_API_KEY.' -InformationAction Continue
    } elseif (Get-Module -ListAvailable -Name Microsoft.PowerShell.SecretManagement) {
        Import-Module -Name Microsoft.PowerShell.SecretManagement

        $vaultApiKey = Get-VaultApiKey -SecretName $SecretName -VaultName $VaultName
        if ($null -ne $vaultApiKey) {
            Write-Information "API key: the '$SecretName' secret." -InformationAction Continue
        }
    }

    if (-not $plainApiKey -and $null -eq $vaultApiKey) {
        $keyHelp = @(
            'No PowerShell Gallery API key found.'
            'Create a key at https://www.powershellgallery.com/account/apikeys, then supply it by any of:'
            "  Set-Secret -Name $SecretName -Secret '<key>'   (stored once, recommended)"
            '  $env:PSGALLERY_API_KEY = ''<key>''            (this session only)'
            "  ./Build/Publish-Module.ps1 -ApiKey '<key>'    (one-off)"
        )

        throw ($keyHelp -join [Environment]::NewLine)
    }
}

# --- 1. Help gates ----------------------------------------------------------------
# Before staging, because a stale-MAML failure should stop the release rather than leave a
# staged tree that nobody notices is wrong.
#
# $WhatIfPreference is cleared for the duration. Preference variables are inherited by
# child scopes, so under -WhatIf it reaches Export-MamlCommandHelp inside Build-Help.ps1,
# which then compiles nothing. Build-Help.ps1 writes only to maml/ and en-US/, both of which
# are rebuilt from committed Markdown, so running it for real under -WhatIf is safe.
if (-not $SkipHelpBuild) {
    $priorWhatIf = $WhatIfPreference
    $WhatIfPreference = $false
    try {
        & (Join-Path $PSScriptRoot 'Build-Help.ps1') -ModuleRoot $ModuleRoot -SkipUpdate | Out-Null
    } finally {
        $WhatIfPreference = $priorWhatIf
    }
    Write-Information 'Help gates passed and MAML rebuilt.' -InformationAction Continue
}

# --- 2. Manifest ------------------------------------------------------------------
$manifestPath = Join-Path $ModuleRoot "$moduleName.psd1"
$manifest = Test-ModuleManifest -Path $manifestPath
$version = $manifest.Version

# Catches the empty-string trap, which otherwise fails the pack with NuGet's opaque
# 'IconUrl cannot be empty' - a message that names neither the manifest nor the key.
foreach ($uriKey in 'IconUri', 'ProjectUri', 'LicenseUri', 'HelpInfoUri') {
    $value = $manifest.PSObject.Properties[$uriKey].Value
    if ($null -ne $value -and [string]::IsNullOrWhiteSpace([string]$value)) {
        throw ("$uriKey is present but empty in the manifest. Remove the key entirely - " +
            'an empty URI fails the NuGet pack.')
    }
}

if (-not $manifest.Description) {
    throw 'The manifest needs a Description; the Gallery rejects a package without one.'
}
if (-not $manifest.Tags) {
    throw 'The manifest needs Tags for the module to be discoverable.'
}
# The Gallery refuses the upload with a 400 when the release notes pass 10,600 characters
# (v0.27.0, the first attempt: 11,319 characters, every version since 0.1.0). Keep the newest
# few in the manifest; CHANGELOG.md ships in the package and holds the rest. The description
# carries NuGet's limit of 4,000, which the Gallery applies.
#
# A line break is counted as two characters, the larger of the two possible counts: the publish
# writes the release notes into the package with the line endings of the system that publishes,
# whatever the manifest has.
#
# The tags are not measured. The publish writes only the manifest's own tags and PSModule; the
# Gallery adds the PSEdition_, PSFunction_, PSCommand_ and PSIncludes_ tags it lists, and that
# list has no 4,000-character limit.
$measurements = @(
    @{ Field = 'Description'; Text = $manifest.Description; Limit = 4000 }
    @{ Field = 'ReleaseNotes'; Text = $manifest.ReleaseNotes; Limit = 10600 }
)
$measured = foreach ($measurement in $measurements) {
    $length = ([string]$measurement.Text).Replace("`r`n", "`n").Replace("`n", "`r`n").Length
    if ($length -gt $measurement.Limit) {
        $problem = "The manifest's $($measurement.Field) is $length characters."
        $advice = if ($measurement.Field -eq 'ReleaseNotes') {
            ' Move the older versions out, CHANGELOG.md has them.'
        } else {
            ''
        }
        throw "$problem The PowerShell Gallery accepts at most $($measurement.Limit).$advice"
    }
    "$($measurement.Field) $length/$($measurement.Limit)"
}
Write-Information "Gallery metadata: $($measured -join ', ') characters." -InformationAction Continue

# --- 3. Already published? --------------------------------------------------------
# A version number is consumed forever on first publish. Learning that from a rejected
# upload is worse than a check costing one request.
if (-not $WhatIfPreference) {
    $findSplat = @{
        Name = $moduleName
        Repository = $Repository
        Version = "$version"
        ErrorAction = 'SilentlyContinue'
    }
    if (Find-PSResource @findSplat) {
        throw ("$moduleName $version is already on $Repository. Gallery versions cannot be replaced - " +
            'bump ModuleVersion and update CHANGELOG.md.')
    }
}

# --- 4. Stage ---------------------------------------------------------------------
# Every staging cmdlet is pinned to -WhatIf:$false. SupportsShouldProcess on this script
# propagates $WhatIfPreference to each of them, so an unpinned -WhatIf run would copy
# nothing and then fail on the empty folder. Staging is not the destructive step and always
# runs for real; only the publish at the end is gated by ShouldProcess.
if (Test-Path -LiteralPath $StagingPath) {
    Remove-Item -LiteralPath $StagingPath -Recurse -Force -WhatIf:$false
}
$stageModule = Join-Path $StagingPath $moduleName
New-Item -Path $stageModule -ItemType Directory -Force -WhatIf:$false | Out-Null

foreach ($file in $shipFiles) {
    $source = Join-Path $ModuleRoot $file
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Shipping file '$file' is missing from the repository root."
    }
    Copy-Item -LiteralPath $source -Destination $stageModule -Force -WhatIf:$false
}

foreach ($folder in $shipFolders) {
    $source = Join-Path $ModuleRoot $folder
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Shipping folder '$folder' is missing from the repository root."
    }
    Copy-Item -LiteralPath $source -Destination $stageModule -Recurse -Force -WhatIf:$false
}

$staged = Get-ChildItem -LiteralPath $stageModule -Recurse -File
$totalKb = [math]::Round(($staged | Measure-Object -Property Length -Sum).Sum / 1KB, 1)

Write-Information "Staged $($staged.Count) file(s), $totalKb KB, to $stageModule" -InformationAction Continue
$staged |
    ForEach-Object { $_.FullName.Substring($stageModule.Length + 1) } |
    Sort-Object |
    ForEach-Object { Write-Information "  $_" -InformationAction Continue }

# --- 5. Prove the staged tree imports ----------------------------------------------
# The staged copy is what users get. If the allowlist dropped something the module needs -
# a Private helper, a rule file, the PSScriptAnalyzer module, the en-US folder holding the
# MAML - it should fail here in a fresh process, not after someone installs it. Every command
# must serve the compiled help: with .EXTERNALHELP on each export there is no comment block to
# fall back on, so a missing or misnamed IntuneScriptLab-Help.xml shows up as a command with
# no description. The analysis is exercised too, on a detection script with the return-before-
# exit mistake, because a module that imports can still be missing the rule that does the work.
$stagedManifest = Join-Path $stageModule "$moduleName.psd1"

# The exported names are compared with FunctionsToExport of the staged manifest, name by name: a
# count that matches can hide one command missing and another exported by mistake.
$check = @"
`$ErrorActionPreference = 'Stop'
Import-Module '$stagedManifest' -Force
`$commands = @((Get-Module $moduleName).ExportedFunctions.Keys | Sort-Object)
`$declared = @((Import-PowerShellDataFile -LiteralPath '$stagedManifest').FunctionsToExport | Sort-Object)
`$difference = @(Compare-Object -ReferenceObject `$declared -DifferenceObject `$commands)
if (`$difference.Count -gt 0) {
    `$names = (`$difference | ForEach-Object { "`$(`$_.InputObject) (`$(`$_.SideIndicator))" }) -join ', '
    throw "Staged module's exports differ from the manifest's FunctionsToExport: `$names"
}
`$sample = Join-Path ([System.IO.Path]::GetTempPath()) "isl-staged-`$([guid]::NewGuid().ToString('N'))"
`$null = New-Item -ItemType Directory -Path (Join-Path `$sample 'Remediations\Widget') -Force
`$detect = Join-Path `$sample 'Remediations\Widget\Detect.ps1'
Set-Content -Path `$detect -Value "if (Test-Path C:\x) { return 'issue' }`r`nexit 1" -Encoding UTF8
`$findings = @(Test-IntuneScript -Path `$detect)
Remove-Item -Path `$sample -Recurse -Force
if ('IslExitCodeIssue' -notin `$findings.RuleName) {
    throw 'Staged module did not report the return-before-exit mistake in the sample detection script.'
}
if (-not (Test-Path (Get-IntuneAnalyzerRulePath))) {
    throw 'Staged module does not ship its PSScriptAnalyzer rules.'
}
`$noHelp = @(foreach (`$name in `$commands) {
    if (-not (Get-Help `$name -Full -ErrorAction SilentlyContinue).Description) { `$name }
})
if (`$noHelp) {
    throw "Staged module served no MAML help for: `$(`$noHelp -join ', ')"
}
if (-not (Get-Help about_$moduleName -ErrorAction SilentlyContinue)) {
    throw 'Staged module does not serve about_$moduleName.'
}
'STAGED-OK'
"@

$result = pwsh -NoProfile -NonInteractive -Command $check 2>&1
if ($LASTEXITCODE -ne 0 -or "$result" -notmatch 'STAGED-OK') {
    throw "The staged module failed verification:`n$($result -join [Environment]::NewLine)"
}
Write-Information ('Staged module imports, exports the declared commands, analyzes a sample script, ships its ' +
    'PSScriptAnalyzer rules and serves MAML help for every command.') -InformationAction Continue

# --- 6. Publish -------------------------------------------------------------------
if (-not $PSCmdlet.ShouldProcess("$moduleName $version -> $Repository", 'Publish')) {
    $left = "WhatIf: nothing published. Staged tree left at $stageModule for inspection."
    Write-Information $left -InformationAction Continue
    return
}

$publishParameters = @{
    Path = $stageModule
    Repository = $Repository
    SkipDependenciesCheck = $true
}
if ($null -ne $vaultApiKey) {
    # Publish-PSResource takes the key as text. The vault's SecureString is converted here, for
    # this call only, and the text is kept in no variable.
    $keyHolder = [System.Net.NetworkCredential]::new('', $vaultApiKey)
    Publish-PSResource @publishParameters -ApiKey $keyHolder.Password
} else {
    Publish-PSResource @publishParameters -ApiKey $plainApiKey
}

Write-Information "Published $moduleName $version to $Repository." -InformationAction Continue
$next = "Indexing takes a few minutes, then: Install-PSResource -Name $moduleName"
Write-Information $next -InformationAction Continue
