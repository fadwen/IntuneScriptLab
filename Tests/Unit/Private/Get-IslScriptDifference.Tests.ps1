#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    How two scripts that are not byte-identical differ: the BOM, the line endings, the content or
    only trailing white space.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    function script:ConvertTo-TestByte {
        param([string]$Text, [switch]$Bom)
        $preamble = [System.Text.UTF8Encoding]::new([bool]$Bom).GetPreamble()
        [byte[]]($preamble + [System.Text.Encoding]::UTF8.GetBytes($Text))
    }

    function script:Get-Difference {
        param([byte[]]$Local, [byte[]]$Tenant)
        InModuleScope IntuneScriptLab -Parameters @{ Local = $Local; Tenant = $Tenant } {
            Get-IslScriptDifference -Local $Local -Tenant $Tenant
        }
    }
}

Describe 'Get-IslScriptDifference' -Tag 'Unit', 'Private' {

    It 'names a byte order mark on one side only' {
        $local = ConvertTo-TestByte "exit 0`r`n" -Bom
        $result = Get-Difference -Local $local -Tenant (ConvertTo-TestByte "exit 0`r`n")

        $result | Should-HaveType 'IntuneScriptLab.ScriptDifference'
        $result.Differences | Should-BeCollection @('Bom')
        $result.Detail | Should-Be "the local file has a BOM, the tenant's has none"
    }

    It 'names line endings that differ' {
        $result = Get-Difference -Local (ConvertTo-TestByte "a`r`nexit 0") -Tenant (ConvertTo-TestByte "a`nexit 0")

        $result.Differences | Should-BeCollection @('LineEndings')
        $result.Detail | Should-Be 'line endings CRLF locally, LF in the tenant'
    }

    It 'names the first line whose content differs and counts the lines only one side has' {
        $result = Get-Difference -Local (ConvertTo-TestByte "a`nb`nc") -Tenant (ConvertTo-TestByte "a`nB`nc`nd")

        $result.Differences | Should-BeCollection @('Content')
        $result.Detail | Should-Be ("content differs from line 2: local 'b', tenant 'B' " +
            '(1 line(s) only local, 2 only in the tenant)')
    }

    It 'compares two scripts of one line each' {
        $local = ConvertTo-TestByte "Write-Output 'abc'"
        $result = Get-Difference -Local $local -Tenant (ConvertTo-TestByte "Write-Output 'abd'")

        $result.Differences | Should-BeCollection @('Content')
        $result.Detail | Should-BeLikeString "content differs from line 1: local 'Write-Output 'abc'', tenant*"
    }

    It 'reports the end of a script that is blank on one side' {
        $result = Get-Difference -Local (ConvertTo-TestByte "`n`n") -Tenant (ConvertTo-TestByte 'exit 0')

        $result.Detail | Should-BeLikeString "content differs from line 1: local '<end>', tenant 'exit 0'*"
    }

    It 'names trailing white space and blank lines at the end as Whitespace' {
        $result = Get-Difference -Local (ConvertTo-TestByte "exit 0   `n`n") -Tenant (ConvertTo-TestByte 'exit 0')

        $result.Differences | Should-BeCollection @('Whitespace')
    }

    It 'counts bytes that differ outside the UTF-8 text as Content' {
        $result = Get-Difference -Local ([byte[]](0x61, 0xFF)) -Tenant ([byte[]](0x61, 0xFE))

        $result.Differences | Should-BeCollection @('Content')
        $result.Detail | Should-Be 'the bytes differ outside the UTF-8 text'
    }
}
