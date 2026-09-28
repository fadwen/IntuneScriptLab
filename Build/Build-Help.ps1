#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Microsoft.PowerShell.PlatyPS'; ModuleVersion = '1.0.3' }

<#
    .SYNOPSIS
        Refreshes the PlatyPS Markdown under docs\ and compiles it into en-US\IntuneScriptLab-Help.xml.

    .DESCRIPTION
        The Markdown in docs\IntuneScriptLab\ is the source of the public command help; the public
        functions carry only .EXTERNALHELP and a one-line synopsis. Run this after changing a public
        function's parameters or editing the Markdown:

            1. Update-MarkdownCommandHelp folds signature changes into the existing Markdown.
            2. The module page is regenerated from the command files.
            3. Test-MarkdownCommandHelp, a relative-link check and a placeholder check gate the build.
            4. Export-MamlCommandHelp compiles the Markdown to en-US\IntuneScriptLab-Help.xml, the file
               Get-Help reads.

        A new public function has no Markdown yet: write its comment-based help first, run
        New-MarkdownCommandHelp for it into docs\, then replace the help block with .EXTERNALHELP
        (see .github\instructions\platyps.instructions.md for why that order matters).

        Update-MarkdownCommandHelp adds an INPUTS heading for every pipeline parameter type it
        finds, with a placeholder body if the Markdown lacks it; the build stops on placeholders,
        so fill the heading in (or delete it) and run again with -SkipUpdate.

    .PARAMETER SkipUpdate
        Compile the Markdown as it is without folding in signature changes first. Useful when the
        Markdown was edited by hand and the module has not changed.

    .EXAMPLE
        .\Build\Build-Help.ps1

        Refreshes docs\ from the loaded module and rebuilds en-US\IntuneScriptLab-Help.xml.

    .EXAMPLE
        .\Build\Build-Help.ps1 -SkipUpdate -Verbose

        Rebuilds the MAML from the current Markdown only, reporting each step.

    .EXAMPLE
        .\Build\Build-Help.ps1; Import-Module .\IntuneScriptLab.psd1 -Force; Get-Help Test-IntuneScript -Full

        Rebuilds the help and shows the compiled result the way a user sees it.

    .INPUTS
        None.

    .OUTPUTS
        None. Files are written under docs\ and en-US\; failures are terminating errors.

    .NOTES
        Author: Jeffrey Stuhr. Update-MarkdownCommandHelp leaves a backup beside each file it
        rewrites; they are removed once the build succeeds because git already holds the previous
        version.

    .LINK
        https://learn.microsoft.com/en-us/powershell/utility-modules/platyps/overview
#>
[CmdletBinding()]
param(
    [switch]$SkipUpdate,

    # Run the checks on the committed Markdown without folding signatures in or compiling: the
    # pull request gate
    [switch]$ValidateOnly,

    # Repository root, the module root; the parent of the folder holding this script
    [ValidateNotNullOrEmpty()]
    [string]$ModuleRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$moduleRoot = $ModuleRoot
if ($ValidateOnly) { $SkipUpdate = $true }
$docs = Join-Path $moduleRoot 'docs\IntuneScriptLab'
$culture = Join-Path $moduleRoot 'en-US'
$maml = Join-Path ([IO.Path]::GetTempPath()) "IntuneScriptLab-maml-$([guid]::NewGuid())"

Import-Module (Join-Path $moduleRoot 'IntuneScriptLab.psd1') -Force
$module = Get-Module IntuneScriptLab

function Export-IslMaml {
    # Compiles docs\IntuneScriptLab\*.md into en-US\IntuneScriptLab-Help.xml
    $null = Measure-PlatyPSMarkdown -Path "$docs\*.md" |
        Where-Object Filetype -match 'CommandHelp' |
        Import-MarkdownCommandHelp -Path { $_.FilePath } |
        Export-MamlCommandHelp -OutputFolder $maml -Force
    $built = Get-ChildItem $maml -Recurse -Filter 'IntuneScriptLab-Help.xml' | Select-Object -First 1
    if (-not $built) {
        throw "Export-MamlCommandHelp produced no IntuneScriptLab-Help.xml under $maml"
    }
    $null = New-Item -ItemType Directory -Path $culture -Force
    Copy-Item $built.FullName (Join-Path $culture 'IntuneScriptLab-Help.xml') -Force
    Remove-Item $maml -Recurse -Force
}

if (-not $SkipUpdate) {
    # A build that stopped on a validation error leaves the update's backups behind, and the next
    # update refuses to overwrite them
    Get-ChildItem $docs -Filter '*.bak' -ErrorAction SilentlyContinue | Remove-Item -Force

    # Update-MarkdownCommandHelp merges every parameter description Get-Help returns, and Get-Help
    # renders the shipped MAML one sentence per line, so the text never equals the Markdown and
    # comes back appended under it on every run. Park the MAML during the update: with no help
    # to merge, the update touches only the syntax and metadata, which is all it is here for.
    $shipped = Join-Path $culture 'IntuneScriptLab-Help.xml'
    $parked = "$shipped.updating"
    if (Test-Path $shipped) { Move-Item $shipped $parked -Force }
    try {
        Import-Module (Join-Path $moduleRoot 'IntuneScriptLab.psd1') -Force

        Write-Verbose 'Folding signature changes into docs\IntuneScriptLab\*.md'
        $null = Measure-PlatyPSMarkdown -Path "$docs\*.md" |
            Where-Object Filetype -match 'CommandHelp' |
            Update-MarkdownCommandHelp -Path { $_.FilePath }

        # Public functions added since the last run have no Markdown yet. Their comment-based
        # help is the seed, so they are generated with the MAML still parked
        $documented = (Get-ChildItem $docs -Filter *.md).BaseName
        $missing = $module.ExportedFunctions.Keys | Where-Object { $_ -notin $documented }
        if ($missing) {
            Write-Verbose "Generating first-time Markdown for: $($missing -join ', ')"
            $markdownHelpSplat = @{
                CommandInfo  = Get-Command $missing
                OutputFolder = Split-Path $docs
                Locale       = 'en-US'
            }
            $null = New-MarkdownCommandHelp @markdownHelpSplat
        }

        Write-Verbose 'Refreshing the module page'
        $null = Measure-PlatyPSMarkdown -Path "$docs\*.md" |
            Where-Object Filetype -match 'CommandHelp' |
            Import-MarkdownCommandHelp -Path { $_.FilePath } |
            Update-MarkdownModuleFile -Path (Join-Path $docs 'IntuneScriptLab.md')
    }
    finally {
        if (Test-Path $parked) { Move-Item $parked $shipped -Force }
    }
}

Write-Verbose 'Validating the Markdown structure'
$invalid = Measure-PlatyPSMarkdown -Path "$docs\*.md" |
    Where-Object Filetype -match 'CommandHelp' |
    Test-MarkdownCommandHelp -Path { $_.FilePath } -DetailView |
    Where-Object { -not $_.IsValid }
if ($invalid) {
    throw "Markdown help failed validation: $(($invalid | ForEach-Object { $_.Path }) -join ', ')"
}

# A relative link passes Test-MarkdownCommandHelp and then breaks Get-Help at read time; only a
# bare topic ([Name]()) or an absolute URL is allowed
$relative = Select-String -Path "$docs\*.md" -Pattern '^\s*-?\s*\[.+\]\((?!https?://|\))'
if ($relative) {
    $where = ($relative | ForEach-Object { "$($_.Filename):$($_.LineNumber)" }) -join ', '
    throw "Relative link in help Markdown: $where"
}

# "{{ Fill in the Description }}" for a new command, "{{ Fill <Name> Description }}" for a new parameter
$unfilled = Select-String -Path "$docs\*.md" -Pattern '\{\{\s*Fill' -List
if ($unfilled) {
    throw "Help templates still contain placeholders: $(($unfilled.Path | Split-Path -Leaf) -join ', ')"
}

if ($ValidateOnly) {
    $count = (Get-ChildItem $docs -Filter *.md).Count
    Write-Information -InformationAction Continue -MessageData (
        "Help Markdown valid: $count files, no placeholders, no relative links")
    return
}

Write-Verbose 'Compiling MAML'
Export-IslMaml

# Backups from Update-MarkdownCommandHelp; git holds the previous version
Get-ChildItem $docs -Filter '*.bak' -ErrorAction SilentlyContinue | Remove-Item -Force

Write-Information -InformationAction Continue -MessageData (
    "Help built: $((Get-ChildItem $docs -Filter *.md).Count) Markdown files, en-US\IntuneScriptLab-Help.xml")
