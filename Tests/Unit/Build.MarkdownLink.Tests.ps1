#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Build/Test-MarkdownLink.ps1, the documentation gate (CIC-14), run in a new process against
    small Markdown files: it must pass the links that work and name each one that does not.
#>

BeforeAll {
    $repositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $buildFolder = Join-Path -Path $repositoryRoot -ChildPath 'Build'
    $script:Checker = Join-Path -Path $buildFolder -ChildPath 'Test-MarkdownLink.ps1'
    $script:Shell = (Get-Process -Id $PID).Path

    function script:Invoke-LinkCheck {
        <#
        .SYNOPSIS
            Runs the link check on Markdown files in a new process.

        .DESCRIPTION
            Writes each file under TestDrive, runs Build/Test-MarkdownLink.ps1 on them with the
            host that runs the tests, and returns what it wrote and its exit code.

        .PARAMETER File
            A hashtable of file name to the lines of the file.

        .EXAMPLE
            Invoke-LinkCheck -File @{ 'a.md' = '# A', '[x](#a)' }

            Checks one file whose only link names its own heading.

        .INPUTS
            None.

        .OUTPUTS
            IntuneScriptLab.Test.LinkCheck. Output and ExitCode.
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
        $pathList = ($paths | ForEach-Object { "'$_'" }) -join ','
        $output = & $script:Shell -NoProfile -NonInteractive -Command "& '$script:Checker' -Path $pathList" 2>&1
        [pscustomobject]@{
            PSTypeName = 'IntuneScriptLab.Test.LinkCheck'
            Output = ($output | ForEach-Object { "$_" }) -join "`n"
            ExitCode = $LASTEXITCODE
        }
    }
}

Describe 'Build/Test-MarkdownLink.ps1' -Tag 'Unit', 'Build' {

    It 'passes anchors, relative files and the links it leaves alone' {
        $result = Invoke-LinkCheck -File @{
            'README.md' = @(
                '# Module', '', '## Quick start', '## `Get-Thing` and [more](https://x.example)', '## Quick start'
                '[a](#quick-start) [b](#get-thing-and-more) [c](#quick-start-1) [d](docs/Page.md#usage)'
                '[e](docs) [f](https://example.com/#x) [g]() [h](mailto:a@example.com)'
            )
            'docs\Page.md' = @('# Page', '## Usage')
        }

        $result.ExitCode | Should-Be 0
        $result.Output | Should-BeLikeString '*5 checked in 2 file(s), none broken*'
    }

    It 'names an anchor that is no heading and a file that does not exist' {
        $result = Invoke-LinkCheck -File @{
            'README.md' = @('# Module', '[a](#install)', '[b](docs/Missing.md)', '[c](Other.md#nowhere)')
            'Other.md' = @('# Other')
        }

        $result.ExitCode | Should-BeGreaterThan 0
        $result.Output | Should-BeLikeString "*README.md:2: '#install' names no heading*"
        $result.Output | Should-BeLikeString "*README.md:3: 'docs/Missing.md' names nothing that exists*"
        $result.Output | Should-BeLikeString "*README.md:4: 'Other.md#nowhere' names no heading*"
        $result.Output | Should-BeLikeString '*3 of 3 link(s)*broken*'
    }

    It 'leaves out links in a fenced code block and in inline code' {
        $result = Invoke-LinkCheck -File @{
            'README.md' = @('# Module', '```markdown', '[a](#missing)', '```', 'Use `[b](#missing)` here.')
        }

        $result.ExitCode | Should-Be 0
        $result.Output | Should-BeLikeString '*0 checked*none broken*'
    }
}
