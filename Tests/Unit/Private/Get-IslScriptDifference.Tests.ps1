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
        <#
        .SYNOPSIS
            Converts text to its UTF-8 bytes, with a byte order mark when asked.

        .DESCRIPTION
            Gives the bytes of a script as the local file or the tenant would hold them, so that
            each test states the encoding of both sides.

        .PARAMETER Text
            The text of the script.

        .PARAMETER Bom
            Puts the UTF-8 byte order mark before the text.

        .EXAMPLE
            ConvertTo-TestByte "exit 0`r`n" -Bom

            Returns the byte order mark followed by the bytes of the text.

        .INPUTS
            None.

        .OUTPUTS
            System.Byte. The bytes, one at a time; the caller collects them into an array.
        #>
        [CmdletBinding()]
        [OutputType([byte])]
        param(
            [string]$Text,

            [switch]$Bom
        )

        $preamble = [System.Text.UTF8Encoding]::new([bool]$Bom).GetPreamble()
        [byte[]]($preamble + [System.Text.Encoding]::UTF8.GetBytes($Text))
    }

    function script:Get-Difference {
        <#
        .SYNOPSIS
            Gets how two scripts differ with Get-IslScriptDifference inside the module.

        .DESCRIPTION
            Get-IslScriptDifference is private, so the test reaches it through InModuleScope.

        .PARAMETER Local
            The bytes of the local file.

        .PARAMETER Tenant
            The bytes of the script in the tenant.

        .EXAMPLE
            Get-Difference -Local (ConvertTo-TestByte 'exit 0' -Bom) -Tenant (ConvertTo-TestByte 'exit 0')

            Returns a difference that names the byte order mark.

        .INPUTS
            None.

        .OUTPUTS
            IntuneScriptLab.ScriptDifference. What differs between the two scripts.
        #>
        [CmdletBinding()]
        [OutputType('IntuneScriptLab.ScriptDifference')]
        param(
            [byte[]]$Local,

            [byte[]]$Tenant
        )

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
