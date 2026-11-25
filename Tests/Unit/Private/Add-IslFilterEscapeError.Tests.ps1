#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The failure for a double quote escaped inside an assignment filter value.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }
}

Describe 'Add-IslFilterEscapeError' -Tag 'Unit', 'Private' {

    It 'names both refused escapes, the position of the value and what to use instead' {
        $failure = InModuleScope IntuneScriptLab {
            $parser = New-IslFilterParser -Rule '(device.deviceName -eq "say \"hi\"")'
            Add-IslFilterEscapeError -Parser $parser -Previous $parser.Tokens[3]
            $parser.Error
        }

        $failure | Should-BeLikeString 'Filter rule: a double quote inside a value cannot be escaped*'
        $failure | Should-BeLikeString '*refuses both \" and ""*'
        $failure | Should-BeLikeString '*(the value at position 24)*'
        $failure | Should-BeLikeString '*-contains or -startsWith instead'
    }

    It 'keeps a failure recorded before it' {
        $failure = InModuleScope IntuneScriptLab {
            $parser = New-IslFilterParser -Rule '"a"'
            Add-IslFilterParseError -Parser $parser -Message 'earlier'
            Add-IslFilterEscapeError -Parser $parser -Previous $parser.Tokens[0]
            $parser.Error
        }

        $failure | Should-Be 'Filter rule: earlier'
    }
}
