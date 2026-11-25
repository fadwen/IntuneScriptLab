#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The first reason an assignment filter rule does not parse is the one kept.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }
}

Describe 'Add-IslFilterParseError' -Tag 'Unit', 'Private' {

    It 'records the message with the Filter rule prefix' {
        $failure = InModuleScope IntuneScriptLab {
            $parser = @{ Error = $null }
            Add-IslFilterParseError -Parser $parser -Message 'the rule is empty'
            $parser.Error
        }

        $failure | Should-Be 'Filter rule: the rule is empty'
    }

    It 'keeps the first failure when a second one is reported' {
        $failure = InModuleScope IntuneScriptLab {
            $parser = @{ Error = $null }
            Add-IslFilterParseError -Parser $parser -Message 'first'
            Add-IslFilterParseError -Parser $parser -Message 'second'
            $parser.Error
        }

        $failure | Should-Be 'Filter rule: first'
    }

    It 'writes nothing to the pipeline' {
        $output = InModuleScope IntuneScriptLab {
            @(Add-IslFilterParseError -Parser @{ Error = $null } -Message 'x')
        }

        $output | Should-BeCollection @()
    }
}
