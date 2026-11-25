#Requires -Version 5.1

<#
.SYNOPSIS
    Checks the anchors and relative links of the repository's Markdown files.

.DESCRIPTION
    The documentation gate of CIC-14. For each link in the files given, outside fenced code blocks
    and inline code:

    - a link to an anchor in the same file ('#quick-start') must name a heading of that file;
    - a relative link ('docs/Rules.md', 'LICENSE') must name a file or folder that exists, read from
      the folder of the file that holds it, and an anchor after it must name a heading of that
      file when it is Markdown;
    - a link to a web address, a mail address or nothing ('[Get-Thing]()', the form PlatyPS uses
      for a command) is not checked.

    Anchors are made from headings as GitHub makes them: lower case, spaces as hyphens, everything
    but letters, digits, hyphens and underscores left out, and a number added to a repeated one.
    The script writes one line for each broken link and fails when there is any, so that CI stops
    on it. File names are compared as the file system compares them; run it on Linux, as CI does,
    to compare them as GitHub does.

.PARAMETER Path
    The Markdown files to check. Wildcards are not expanded. Default: the Markdown files at the
    root of the repository, the top level of docs and the two of Validation.

.EXAMPLE
    ./Build/Test-MarkdownLink.ps1

    Checks the default files and writes how many links it checked.

.EXAMPLE
    ./Build/Test-MarkdownLink.ps1 -Path ./README.md

    Checks README.md only.

.INPUTS
    None.

.OUTPUTS
    None. A line for each broken link, then a summary, as information records.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
if (-not $Path) {
    $docsFolder = Join-Path -Path $repositoryRoot -ChildPath 'docs'
    $validationFolder = Join-Path -Path $repositoryRoot -ChildPath 'Validation'
    $Path = @(
        Get-ChildItem -LiteralPath $repositoryRoot -Filter '*.md' -File
        Get-ChildItem -LiteralPath $docsFolder -Filter '*.md' -File
        Get-ChildItem -LiteralPath $validationFolder -Filter '*.md' -File
    ) | ForEach-Object { $_.FullName }
}

function Get-MarkdownAnchor {
    <#
    .SYNOPSIS
        Gets the anchors GitHub makes from the headings of a Markdown text.

    .DESCRIPTION
        Every ATX heading ('# Title' to '###### Title') outside a fenced code block gives one
        anchor: lower case, inline code marks and links reduced to their text, everything but
        letters, digits, spaces, hyphens and underscores left out, spaces turned into hyphens, and
        '-1', '-2' added to a repeated one. An explicit '<a name="x">' or '<a id="x">' gives 'x'.

    .PARAMETER Line
        The lines of the file.

    .EXAMPLE
        Get-MarkdownAnchor -Line '## Quick start', '## Quick start'

        Returns 'quick-start' and 'quick-start-1'.

    .INPUTS
        None.

    .OUTPUTS
        System.String. One anchor for each heading.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string[]]$Line
    )

    $seen = @{}
    $inFence = $false
    foreach ($text in $Line) {
        if ($text -match '^\s*(```|~~~)') {
            $inFence = -not $inFence
            continue
        }
        if ($inFence) {
            continue
        }
        foreach ($explicit in [regex]::Matches($text, '<a\s+(?:name|id)="([^"]+)"')) {
            $explicit.Groups[1].Value
        }
        if ($text -notmatch '^#{1,6}\s+(.+?)\s*#*\s*$') {
            continue
        }
        $heading = $Matches[1]
        # A link keeps its text, inline code its content
        $heading = [regex]::Replace($heading, '\[([^\]]*)\]\([^)]*\)', '$1')
        $heading = $heading.Replace('`', '')
        $slug = $heading.ToLowerInvariant()
        $slug = [regex]::Replace($slug, '[^\p{L}\p{Nd}\s_-]', '')
        $slug = $slug.Replace(' ', '-')
        if ($seen.ContainsKey($slug)) {
            $seen[$slug]++
            "$slug-$($seen[$slug])"
        } else {
            $seen[$slug] = 0
            $slug
        }
    }
}


$anchorCache = @{}
$broken = [System.Collections.Generic.List[string]]::new()
$checked = 0
foreach ($file in $Path) {
    $fullPath = (Resolve-Path -LiteralPath $file).ProviderPath
    $folder = Split-Path -Path $fullPath -Parent
    $lines = @([System.IO.File]::ReadAllLines($fullPath))
    if (-not $anchorCache.ContainsKey($fullPath)) {
        $anchorCache[$fullPath] = @(Get-MarkdownAnchor -Line $lines)
    }
    $inFence = $false
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $text = $lines[$index]
        if ($text -match '^\s*(```|~~~)') {
            $inFence = -not $inFence
            continue
        }
        if ($inFence) {
            continue
        }
        $outsideCode = [regex]::Replace($text, '`[^`]*`', '')
        foreach ($link in [regex]::Matches($outsideCode, '!?\[[^\]]*\]\(([^)\s]*)(?:\s+"[^"]*")?\)')) {
            $target = $link.Groups[1].Value
            if (-not $target -or $target -match '^(https?|mailto):') {
                continue
            }
            $checked++
            $shown = if ($fullPath.StartsWith($repositoryRoot + [System.IO.Path]::DirectorySeparatorChar)) {
                $fullPath.Substring($repositoryRoot.Length + 1)
            } else { $fullPath }
            $place = '{0}:{1}' -f $shown, ($index + 1)
            $pathPart, $anchor = $target -split '#', 2
            $linkedFile = $fullPath
            if ($pathPart) {
                $linkedFile = [System.IO.Path]::GetFullPath((Join-Path -Path $folder -ChildPath $pathPart))
                if (-not (Test-Path -LiteralPath $linkedFile)) {
                    $broken.Add("${place}: '$target' names nothing that exists")
                    continue
                }
            }
            $isFolder = Test-Path -LiteralPath $linkedFile -PathType Container
            if (-not $anchor -or $linkedFile -notlike '*.md' -or $isFolder) {
                continue
            }
            if (-not $anchorCache.ContainsKey($linkedFile)) {
                $linkedLines = @([System.IO.File]::ReadAllLines($linkedFile))
                $anchorCache[$linkedFile] = @(Get-MarkdownAnchor -Line $linkedLines)
            }
            if ($anchor -notin $anchorCache[$linkedFile]) {
                $broken.Add("${place}: '$target' names no heading of that file")
            }
        }
    }
}

foreach ($line in $broken) {
    Write-Information -MessageData $line -InformationAction Continue
}
if ($broken.Count -gt 0) {
    throw "$($broken.Count) of $checked link(s) in $(@($Path).Count) Markdown file(s) are broken."
}
Write-Information -InformationAction Continue -MessageData (
    "Markdown links: $checked checked in $(@($Path).Count) file(s), none broken.")
