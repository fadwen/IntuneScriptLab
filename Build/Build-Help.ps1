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
            3. Test-MarkdownCommandHelp, a relative-link check, a placeholder check and a drift check
               gate the build. The drift check compares the documented commands with the exported
               ones, and each command's documented parameters with its real ones.
            4. Export-MamlCommandHelp compiles the Markdown to en-US\IntuneScriptLab-Help.xml, the file
               Get-Help reads.

        A new public function has no Markdown yet: write its comment-based help first, run
        New-MarkdownCommandHelp for it into docs\, then replace the help block with .EXTERNALHELP
        (see .github\instructions\powershell-platyps.instructions.md for why that order matters).

        Update-MarkdownCommandHelp adds an INPUTS heading for every pipeline parameter type it
        finds, with a placeholder body if the Markdown lacks it; the build stops on placeholders,
        so fill the heading in (or delete it) and run again with -SkipUpdate.

    .PARAMETER SkipUpdate
        Compile the Markdown as it is without folding in signature changes first. Useful when the
        Markdown was edited by hand and the module has not changed.

    .PARAMETER ValidateOnly
        Run the checks on the committed Markdown without folding signatures in and without
        compiling: the pull request gate. Nothing is written.

    .PARAMETER ModuleRoot
        The repository root, which is the module root. Defaults to the parent of the folder that
        holds this script.

    .EXAMPLE
        .\Build\Build-Help.ps1

        Refreshes docs\ from the loaded module and rebuilds en-US\IntuneScriptLab-Help.xml.

    .EXAMPLE
        .\Build\Build-Help.ps1 -ValidateOnly

        Checks the committed Markdown for structure, placeholders, relative links and drift from the
        module, and writes nothing.

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
    [Parameter()]
    [switch]$SkipUpdate,

    [Parameter()]
    [switch]$ValidateOnly,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ModuleRoot = (Split-Path -Path $PSScriptRoot -Parent)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -ValidateOnly reads the committed Markdown as it is, so it implies -SkipUpdate
$skipSignatureUpdate = $SkipUpdate -or $ValidateOnly
$docsRoot = Join-Path -Path $ModuleRoot -ChildPath 'docs'
$docs = Join-Path -Path $docsRoot -ChildPath 'IntuneScriptLab'
$markdownPattern = Join-Path -Path $docs -ChildPath '*.md'
$culture = Join-Path -Path $ModuleRoot -ChildPath 'en-US'
$shipped = Join-Path -Path $culture -ChildPath 'IntuneScriptLab-Help.xml'
$maml = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "IntuneScriptLab-maml-$([guid]::NewGuid())"
$manifestPath = Join-Path -Path $ModuleRoot -ChildPath 'IntuneScriptLab.psd1'

Import-Module -Name $manifestPath -Force
$module = Get-Module -Name IntuneScriptLab

if (-not $skipSignatureUpdate) {
    # A build that stopped on a validation error leaves the update's backups behind, and the next
    # update refuses to overwrite them
    Get-ChildItem -LiteralPath $docs -Filter '*.bak' -ErrorAction SilentlyContinue | Remove-Item -Force

    # Update-MarkdownCommandHelp merges every parameter description Get-Help returns, and Get-Help
    # renders the shipped MAML one sentence per line, so the text never equals the Markdown and
    # comes back appended under it on every run. Park the MAML during the update: with no help
    # to merge, the update touches only the syntax and metadata, which is all it is here for.
    $parked = "$shipped.updating"
    if (Test-Path -LiteralPath $shipped) {
        Move-Item -LiteralPath $shipped -Destination $parked -Force
    }
    try {
        Import-Module -Name $manifestPath -Force

        # Update-MarkdownCommandHelp and New-MarkdownCommandHelp of Microsoft.PowerShell.PlatyPS
        # 1.0.3 end with "The property 'defaultValue' cannot be found on this object" for a
        # command that has parameters when strict mode is on in the scope that calls them. Each
        # therefore runs in a child scope with strict mode off; the rest of the script keeps it.
        Write-Verbose 'Folding signature changes into docs\IntuneScriptLab\*.md'
        & {
            Set-StrictMode -Off
            $null = Measure-PlatyPSMarkdown -Path $markdownPattern |
                Where-Object -Property Filetype -Match -Value 'CommandHelp' |
                Update-MarkdownCommandHelp -Path { $_.FilePath }
        }

        # Public functions added since the last run have no Markdown yet. Their comment-based
        # help is the seed, so they are generated with the MAML still parked
        $documented = @(Get-ChildItem -LiteralPath $docs -Filter '*.md' | ForEach-Object { $_.BaseName })
        $missing = @($module.ExportedFunctions.Keys | Where-Object { $_ -notin $documented })
        if ($missing.Count -gt 0) {
            Write-Verbose "Generating first-time Markdown for: $($missing -join ', ')"
            $markdownHelpParameters = @{
                CommandInfo = Get-Command -Name $missing
                OutputFolder = $docsRoot
                Locale = 'en-US'
            }
            & {
                Set-StrictMode -Off
                $null = New-MarkdownCommandHelp @markdownHelpParameters
            }
        }

        Write-Verbose 'Refreshing the module page'
        $null = Measure-PlatyPSMarkdown -Path $markdownPattern |
            Where-Object -Property Filetype -Match -Value 'CommandHelp' |
            Import-MarkdownCommandHelp -Path { $_.FilePath } |
            Update-MarkdownModuleFile -Path (Join-Path -Path $docs -ChildPath 'IntuneScriptLab.md')
    } finally {
        if (Test-Path -LiteralPath $parked) {
            Move-Item -LiteralPath $parked -Destination $shipped -Force
        }
    }
}

Write-Verbose 'Validating the Markdown structure'
$invalid = @(Measure-PlatyPSMarkdown -Path $markdownPattern |
        Where-Object -Property Filetype -Match -Value 'CommandHelp' |
        Test-MarkdownCommandHelp -Path { $_.FilePath } -DetailView |
        Where-Object { -not $_.IsValid })
if ($invalid.Count -gt 0) {
    throw "Markdown help failed validation: $(($invalid | ForEach-Object { $_.Path }) -join ', ')"
}

# A relative link passes Test-MarkdownCommandHelp and then breaks Get-Help at read time; only a
# bare topic ([Name]()) or an absolute URL is allowed
$relative = @(Select-String -Path $markdownPattern -Pattern '^\s*-?\s*\[.+\]\((?!https?://|\))')
if ($relative.Count -gt 0) {
    $places = ($relative | ForEach-Object { "$($_.Filename):$($_.LineNumber)" }) -join ', '
    throw "Relative link in help Markdown: $places"
}

# Any placeholder in double braces: "{{ Fill in the Description }}" for a new command,
# "{{ Fill <Name> Description }}" for a new parameter
$unfilled = @(Select-String -Path $markdownPattern -Pattern '\{\{[^}]*\}\}' -List)
if ($unfilled.Count -gt 0) {
    $names = ($unfilled | ForEach-Object { Split-Path -Path $_.Path -Leaf }) -join ', '
    throw "Help templates still contain placeholders: $names"
}

# Drift: the Markdown is the help a user reads, so a command or parameter it does not know of, or
# one it still documents after the code dropped it, is stale help. Compared on the loaded module,
# which is the one in this tree
Write-Verbose 'Comparing the documented commands and parameters with the module'
$commandPages = @(Measure-PlatyPSMarkdown -Path $markdownPattern |
        Where-Object -Property Filetype -Match -Value 'CommandHelp')
$documentedCommands = @($commandPages |
        ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.FilePath) })
$exportedCommands = @($module.ExportedFunctions.Keys)
$drift = [System.Collections.Generic.List[string]]::new()
foreach ($name in $exportedCommands | Where-Object { $_ -notin $documentedCommands } | Sort-Object) {
    $drift.Add("$name is exported and has no help Markdown")
}
foreach ($name in $documentedCommands | Where-Object { $_ -notin $exportedCommands } | Sort-Object) {
    $drift.Add("$name has help Markdown and is not exported")
}
$commonParameters = @([System.Management.Automation.PSCmdlet]::CommonParameters) +
    @([System.Management.Automation.PSCmdlet]::OptionalCommonParameters)
foreach ($page in $commandPages) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($page.FilePath)
    if ($name -notin $exportedCommands) { continue }
    $help = Import-MarkdownCommandHelp -Path $page.FilePath
    $documented = @($help.Parameters | ForEach-Object { $_.Name } | Where-Object { $_ -notin $commonParameters })
    $actual = @((Get-Command -Name $name -Module IntuneScriptLab).Parameters.Keys |
            Where-Object { $_ -notin $commonParameters })
    $undocumented = @($actual | Where-Object { $_ -notin $documented } | Sort-Object)
    $stale = @($documented | Where-Object { $_ -notin $actual } | Sort-Object)
    if ($undocumented.Count -gt 0) { $drift.Add("$name does not document -$($undocumented -join ', -')") }
    if ($stale.Count -gt 0) { $drift.Add("$name documents -$($stale -join ', -'), which it no longer has") }
}
if ($drift.Count -gt 0) {
    throw "Help Markdown is out of date. Run .\Build\Build-Help.ps1 and commit the result: $($drift -join '; ')"
}

$markdownCount = @(Get-ChildItem -LiteralPath $docs -Filter '*.md').Count
if ($ValidateOnly) {
    Write-Information -InformationAction Continue -MessageData (
        "Help Markdown valid: $markdownCount files, every exported command and parameter documented, " +
        'no placeholders, no relative links')
    return
}

Write-Verbose 'Compiling MAML'
$null = Measure-PlatyPSMarkdown -Path $markdownPattern |
    Where-Object -Property Filetype -Match -Value 'CommandHelp' |
    Import-MarkdownCommandHelp -Path { $_.FilePath } |
    Export-MamlCommandHelp -OutputFolder $maml -Force
$built = Get-ChildItem -LiteralPath $maml -Recurse -Filter 'IntuneScriptLab-Help.xml' | Select-Object -First 1
if ($null -eq $built) {
    throw "Export-MamlCommandHelp produced no IntuneScriptLab-Help.xml under $maml"
}
$null = New-Item -ItemType Directory -Path $culture -Force

# Export-MamlCommandHelp writes the line endings of the platform, CRLF on Windows. The committed
# file is stored and checked out with LF and CI compares a new build with it byte for byte, so
# the carriage return of every CRLF pair is dropped and the file is the same wherever it is
# built. Bytes, not text: the byte order mark and everything else stay exactly as PlatyPS wrote
# them.
$builtBytes = [System.IO.File]::ReadAllBytes($built.FullName)
$shippedStream = [System.IO.MemoryStream]::new($builtBytes.Length)
try {
    # The bytes between one CRLF pair and the next are copied as a block. A carriage return that
    # no line feed follows is not part of a pair and stays where it is.
    $copyFrom = 0
    $searchFrom = 0
    while ($searchFrom -lt $builtBytes.Length) {
        $carriageReturn = [Array]::IndexOf($builtBytes, [byte]13, $searchFrom)
        if ($carriageReturn -lt 0) {
            break
        }

        $searchFrom = $carriageReturn + 1
        if ($searchFrom -lt $builtBytes.Length -and $builtBytes[$searchFrom] -eq 10) {
            $shippedStream.Write($builtBytes, $copyFrom, $carriageReturn - $copyFrom)
            $copyFrom = $searchFrom
        }
    }
    $shippedStream.Write($builtBytes, $copyFrom, $builtBytes.Length - $copyFrom)
    [System.IO.File]::WriteAllBytes($shipped, $shippedStream.ToArray())
} finally {
    $shippedStream.Dispose()
}
Remove-Item -LiteralPath $maml -Recurse -Force

# Backups from Update-MarkdownCommandHelp; git holds the previous version
Get-ChildItem -LiteralPath $docs -Filter '*.bak' -ErrorAction SilentlyContinue | Remove-Item -Force

Write-Information -InformationAction Continue -MessageData (
    "Help built: $markdownCount Markdown files, en-US\IntuneScriptLab-Help.xml")
