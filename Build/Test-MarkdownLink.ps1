#Requires -Version 5.1

<#
.SYNOPSIS
    Checks the anchors and relative links of the repository's Markdown files.

.DESCRIPTION
    The documentation gate of CIC-14. For each link in the files given, outside fenced code blocks
    and inline code:

    - a link to an anchor in the same file ('#quick-start') must name a heading of that file;
    - a relative link ('docs/Rules.md', 'LICENSE') must name a file or folder that exists, read from
      the folder of the file that holds it, or from the repository root when it starts with '/'.
      A percent-encoded name is decoded first. An anchor after a Markdown file must name a heading
      of that file;
    - a link to a web address, a mail address or nothing ('[Get-Thing]()', the form PlatyPS uses
      for a command) is not checked.

    Inline links and images are read, the outer link of a badge among them, and so are the
    definitions of reference-style links ('[ref]: docs/Rules.md'). A reference ('[text][ref]')
    must have a definition in its file.

    Anchors are made from headings as GitHub makes them: the heading's text, with inline code
    marks, link targets and emphasis markers left out, in lower case, with everything but letters,
    digits, spaces, hyphens and underscores left out, spaces as hyphens, and a number added to a
    repeated one. ATX headings ('## Title', indented up to three spaces), setext headings (a line
    underlined with '=' or '-') and explicit '<a name="x">' or '<a id="x">' give anchors. A fenced
    block ends only at a fence of the same character, at least as long as the one that opened it.

    The script writes one line for each broken link and fails when there is any, so that CI stops
    on it. File names are compared as the file system compares them; run it on Linux, as CI does,
    to compare them as GitHub does.

.PARAMETER Path
    The Markdown files to check. Wildcards are not expanded. Default: the Markdown files at the
    root of the repository, the top level of docs and the two of Validation.

.PARAMETER Root
    The folder a link that starts with '/' is read from, and the folder that names are shown
    relative to. Default: the repository that holds the script.

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
    [string[]]$Path,

    [Parameter()]
    [string]$Root
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1 has no $PSScriptRoot while it binds the parameters, so the default is set here
if (-not $Root) {
    $Root = Split-Path -Path $PSScriptRoot -Parent
}
$repositoryRoot = (Resolve-Path -LiteralPath $Root).ProviderPath.TrimEnd('\', '/')
if (-not $Path) {
    $docsFolder = Join-Path -Path $repositoryRoot -ChildPath 'docs'
    $validationFolder = Join-Path -Path $repositoryRoot -ChildPath 'Validation'
    $Path = @(
        Get-ChildItem -LiteralPath $repositoryRoot -Filter '*.md' -File
        Get-ChildItem -LiteralPath $docsFolder -Filter '*.md' -File
        Get-ChildItem -LiteralPath $validationFolder -Filter '*.md' -File
    ) | ForEach-Object { $_.FullName }
}

function Get-MarkdownLine {
    <#
    .SYNOPSIS
        Gets the lines of a Markdown text that are not inside a fenced code block.

    .DESCRIPTION
        A fence is a line of at least three backticks or tildes, indented up to three spaces. The
        block it opens ends only at a fence of the same character that is at least as long, so a
        shorter fence or one of the other character inside it is part of the block. Each line
        outside a block, the fences themselves left out, is returned with its line number.

    .PARAMETER Line
        The lines of the file.

    .EXAMPLE
        Get-MarkdownLine -Line '# A', '````', '```', '````', 'text'

        Returns line 1 and line 5.

    .INPUTS
        None.

    .OUTPUTS
        IntuneScriptLab.Build.MarkdownLine. Number and Text.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.Build.MarkdownLine')]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [string[]]$Line
    )

    $fence = $null
    for ($index = 0; $index -lt $Line.Count; $index++) {
        $text = $Line[$index]
        $match = [regex]::Match($text, '^ {0,3}(`{3,}|~{3,})')
        if ($null -eq $fence) {
            if ($match.Success) {
                $fence = $match.Groups[1].Value
                continue
            }
            [pscustomobject]@{
                PSTypeName = 'IntuneScriptLab.Build.MarkdownLine'
                Number = $index + 1
                Text = $text
            }
        } elseif ($match.Success -and $match.Groups[1].Value[0] -eq $fence[0] -and
            $match.Groups[1].Value.Length -ge $fence.Length -and $text.Trim().Trim($fence[0]) -eq '') {
            $fence = $null
        }
    }
}


function Get-MarkdownAnchor {
    <#
    .SYNOPSIS
        Gets the anchors GitHub makes from the headings of a Markdown text.

    .DESCRIPTION
        ATX headings ('# Title' to '###### Title', indented up to three spaces) and setext headings
        (a line of text underlined with '=' or '-') outside a fenced code block each give one
        anchor: the text with inline code marks, link targets and emphasis markers left out, in
        lower case, with everything but letters, digits, spaces, hyphens and underscores left out,
        spaces turned into hyphens, and '-1', '-2' added to a repeated one. An explicit
        '<a name="x">' or '<a id="x">' gives 'x'.

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
        [AllowEmptyCollection()]
        [string[]]$Line
    )

    $seen = @{}
    $previous = $null
    foreach ($entry in @(Get-MarkdownLine -Line $Line)) {
        $text = $entry.Text
        foreach ($explicit in [regex]::Matches($text, '<a\s+(?:name|id)="([^"]+)"')) {
            $explicit.Groups[1].Value
        }
        $heading = $null
        if ($text -match '^ {0,3}#{1,6}\s+(.+?)\s*#*\s*$') {
            $heading = $Matches[1]
        } elseif ($null -ne $previous -and $previous.Number -eq $entry.Number - 1 -and
            $previous.Text.Trim() -ne '' -and $previous.Text -notmatch '^ {0,3}(#|>|[-*+] |\d+\. |\|)' -and
            $text -match '^ {0,3}(=+|-+)\s*$') {
            $heading = $previous.Text.Trim()
        }
        $previous = $entry
        if ($null -eq $heading) {
            continue
        }
        # A link keeps its text, inline code its content, emphasis its words
        $heading = [regex]::Replace($heading, '\[([^\]]*)\]\([^)]*\)', '$1')
        $heading = $heading.Replace('`', '')
        $emphasis = '(?<![\p{L}\p{Nd}])(__|_)(?=\S)(.+?)(?<=\S)\1(?![\p{L}\p{Nd}])'
        $heading = [regex]::Replace($heading, $emphasis, '$2')
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
    $allLines = @([System.IO.File]::ReadAllLines($fullPath))
    if (-not $anchorCache.ContainsKey($fullPath)) {
        $anchorCache[$fullPath] = @(Get-MarkdownAnchor -Line $allLines)
    }
    $shown = if ($fullPath.StartsWith($repositoryRoot + [System.IO.Path]::DirectorySeparatorChar)) {
        $fullPath.Substring($repositoryRoot.Length + 1)
    } else { $fullPath }
    $lines = @(Get-MarkdownLine -Line $allLines)

    # Reference-style links: the definitions are targets of their own, and a reference needs one
    $definitions = @{}
    $targets = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $lines) {
        $definition = [regex]::Match($entry.Text, '^ {0,3}\[([^\]]+)\]:\s*<?([^\s>]+)>?')
        if ($definition.Success) {
            $definitions[$definition.Groups[1].Value.ToLowerInvariant()] = $true
            $targets.Add([pscustomobject]@{ Number = $entry.Number; Target = $definition.Groups[2].Value })
            continue
        }
        $outsideCode = [regex]::Replace($entry.Text, '`[^`]*`', '')
        # Every '](target)' is a link: an inline link, an image, and the outer link of a badge
        foreach ($link in [regex]::Matches($outsideCode, '\]\(([^)\s]*)(?:\s+"[^"]*")?\)')) {
            $targets.Add([pscustomobject]@{ Number = $entry.Number; Target = $link.Groups[1].Value })
        }
        foreach ($reference in [regex]::Matches($outsideCode, '\]\[([^\]]+)\]')) {
            $targets.Add([pscustomobject]@{ Number = $entry.Number; Reference = $reference.Groups[1].Value })
        }
    }

    foreach ($item in $targets) {
        $place = '{0}:{1}' -f $shown, $item.Number
        if ($item.PSObject.Properties['Reference']) {
            $checked++
            if (-not $definitions.ContainsKey($item.Reference.ToLowerInvariant())) {
                $broken.Add("${place}: reference '[$($item.Reference)]' has no definition")
            }
            continue
        }
        $target = $item.Target
        if (-not $target -or $target -match '^(https?|mailto):') {
            continue
        }
        $checked++
        $pathPart, $anchor = $target -split '#', 2
        $linkedFile = $fullPath
        if ($pathPart) {
            $decoded = [System.Uri]::UnescapeDataString($pathPart)
            $base = if ($decoded.StartsWith('/')) { $repositoryRoot } else { $folder }
            $linkedFile = [System.IO.Path]::GetFullPath((Join-Path -Path $base -ChildPath $decoded.TrimStart('/')))
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

foreach ($line in $broken) {
    Write-Information -MessageData $line -InformationAction Continue
}
if ($broken.Count -gt 0) {
    throw "$($broken.Count) of $checked link(s) in $(@($Path).Count) Markdown file(s) are broken."
}
Write-Information -InformationAction Continue -MessageData (
    "Markdown links: $checked checked in $(@($Path).Count) file(s), none broken.")
