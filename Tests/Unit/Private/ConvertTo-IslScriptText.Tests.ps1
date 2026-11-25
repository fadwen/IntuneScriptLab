#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    A script's bytes as UTF-8 text, with its byte order mark reported apart.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }
}

Describe 'ConvertTo-IslScriptText' -Tag 'Unit', 'Private' {

    It 'leaves the byte order mark out of the text and reports it' {
        $result = InModuleScope IntuneScriptLab {
            $bytes = [System.Text.UTF8Encoding]::new($true).GetPreamble() +
                [System.Text.Encoding]::UTF8.GetBytes('exit 0')
            ConvertTo-IslScriptText -Bytes $bytes
        }

        $result | Should-HaveType 'IntuneScriptLab.ScriptText'
        $result.Bom | Should-BeTrue
        $result.Text | Should-Be 'exit 0'
    }

    It 'reads bytes without a mark as UTF-8, a character outside ASCII included' {
        # U+00FC, written as its two UTF-8 bytes
        $result = InModuleScope IntuneScriptLab { ConvertTo-IslScriptText -Bytes ([byte[]](0x47, 0xC3, 0xBC)) }

        $result.Bom | Should-BeFalse
        $result.Text | Should-Be ('G' + [char]0x00FC)
    }
}
