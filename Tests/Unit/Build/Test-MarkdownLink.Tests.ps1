#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Build/Test-MarkdownLink.ps1, the documentation gate (CIC-14), run against small Markdown files:
    it must pass the links that work and name each one that does not. The script is called in this
    process with its arguments, and what it writes is read from the information stream.
#>

BeforeAll {
    $repositoryRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    $buildFolder = Join-Path -Path $repositoryRoot -ChildPath 'Build'
    $script:Checker = Join-Path -Path $buildFolder -ChildPath 'Test-MarkdownLink.ps1'

    function script:Invoke-LinkCheck {
        <#
        .SYNOPSIS
            Runs the link check on Markdown files and returns what it wrote.

        .DESCRIPTION
            Writes each file under TestDrive, runs Build/Test-MarkdownLink.ps1 on them, and returns
            the lines it wrote, the message of the error it ended with, if any, and whether it
            passed.

        .PARAMETER File
            A hashtable of file name, relative to a new folder, to the lines of the file.

        .EXAMPLE
            Invoke-LinkCheck -File @{ 'a.md' = '# A', '[x](#a)' }

            Checks one file whose only link names its own heading.

        .INPUTS
            None.

        .OUTPUTS
            IntuneScriptLab.Test.LinkCheck. Output, Failure and Passed.
        #>
        [CmdletBinding()]
        [OutputType('IntuneScriptLab.Test.LinkCheck')]
        param(
            [Parameter(Mandatory)]
            [hashtable]$File
        )

        $folder = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $folder
        $paths = foreach ($name in $File.Keys) {
            $full = Join-Path -Path $folder -ChildPath $name
            $null = New-Item -ItemType Directory -Path (Split-Path -Path $full -Parent) -Force
            [System.IO.File]::WriteAllLines($full, [string[]]$File[$name])
            $full
        }
        $failure = $null
        $output = try {
            & $script:Checker -Path $paths -Root $folder 6>&1
        } catch {
            $failure = $_.Exception.Message
        }
        [pscustomobject]@{
            PSTypeName = 'IntuneScriptLab.Test.LinkCheck'
            Output = (@($output) | ForEach-Object { "$_" }) -join "`n"
            Failure = $failure
            Passed = $null -eq $failure
        }
    }
}

Describe 'Build/Test-MarkdownLink.ps1' -Tag 'Unit', 'Build' {

    Context 'Links that work' {
        It 'passes anchors, relative files and the links it leaves alone' {
            $result = Invoke-LinkCheck -File @{
                'README.md' = @(
                    '# Module', '', '## Quick start', '## `Get-Thing` and [more](https://x.example)'
                    '## Quick start'
                    '[a](#quick-start) [b](#get-thing-and-more) [c](#quick-start-1) [d](docs/Page.md#usage)'
                    '[e](docs) [f](https://example.com/#x) [g]() [h](mailto:a@example.com)'
                )
                'docs\Page.md' = @('# Page', '## Usage')
            }

            $result.Passed | Should-BeTrue
            $result.Output | Should-BeLikeString '*5 checked in 2 file(s), none broken*'
        }

        It 'reads setext and indented headings, and leaves emphasis out of an anchor' {
            $result = Invoke-LinkCheck -File @{
                'README.md' = @(
                    'Setext title', '============', '', 'Second part', '-----------', '   ## Indented'
                    '## _Under_ score and __strong__ words'
                    '[a](#setext-title) [b](#second-part) [c](#indented) [d](#under-score-and-strong-words)'
                )
            }

            $result.Passed | Should-BeTrue
            $result.Output | Should-BeLikeString '*4 checked*none broken*'
        }

        It 'reads a root-relative and a percent-encoded target, a badge and a reference' {
            $result = Invoke-LinkCheck -File @{
                'docs\A.md' = @(
                    '# A', '[a](/docs/My%20File.md) [![badge](/docs/img.svg)](/docs/A.md#a)'
                    '[text][ref]', '', '[ref]: ../LICENSE'
                )
                'docs\My File.md' = @('# File')
                'docs\img.svg' = @('<svg/>')
                'LICENSE' = @('MIT')
            }

            $result.Passed | Should-BeTrue
            # The link, the badge's image and its outer link, the reference and its definition
            $result.Output | Should-BeLikeString '*5 checked in 4 file(s), none broken*'
        }
    }

    Context 'Text that is not a link' {
        It 'leaves a footnote and an index in prose alone' {
            $result = Invoke-LinkCheck -File @{
                'README.md' = @(
                    '# Module', 'A note.[^1] The cell $rows[0][1] holds it.', '', '[^1]: See the docs.'
                )
            }

            $result.Passed | Should-BeTrue
            $result.Output | Should-BeLikeString '*0 checked*none broken*'
        }
    }

    Context 'Links that do not work' {
        It 'names an anchor that is no heading and a file that does not exist' {
            $result = Invoke-LinkCheck -File @{
                'README.md' = @('# Module', '[a](#install)', '[b](docs/Missing.md)', '[c](Other.md#nowhere)')
                'Other.md' = @('# Other')
            }

            $result.Passed | Should-BeFalse
            $result.Output | Should-BeLikeString "*README.md:2: '#install' names no heading*"
            $result.Output | Should-BeLikeString "*README.md:3: 'docs/Missing.md' names nothing that exists*"
            $result.Output | Should-BeLikeString "*README.md:4: 'Other.md#nowhere' names no heading*"
            $result.Failure | Should-BeLikeString '*3 of 3 link(s)*broken*'
        }

        It 'names a reference without a definition and a broken definition' {
            $result = Invoke-LinkCheck -File @{
                'README.md' = @('# Module', '[text][missing] [more][gone]', '', '[gone]: docs/Gone.md')
            }

            # Contains, not a wildcard pattern: brackets are a character class there
            $result.Output.Contains("README.md:2: reference '[missing]' has no definition") | Should-BeTrue
            $result.Output.Contains("README.md:4: 'docs/Gone.md' names nothing that exists") | Should-BeTrue
            $result.Passed | Should-BeFalse
        }
    }

    Context 'Code' {
        It 'leaves out links in a fenced block, a longer fence around a shorter one, and inline code' {
            $result = Invoke-LinkCheck -File @{
                'README.md' = @(
                    '# Module', '````markdown', '```', '[a](#missing)', '```', '[b](#missing)', '````'
                    'Use `[c](#missing)` here.', '~~~', '```', '[d](#missing)', '~~~', '[e](#module)'
                )
            }

            $result.Passed | Should-BeTrue
            $result.Output | Should-BeLikeString '*1 checked*none broken*'
        }
    }
}
