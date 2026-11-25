#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    A whole assignment filter expression: groups of and-joined clauses joined by or.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }

    function script:Read-Expression {
        param([string]$Text)
        InModuleScope IntuneScriptLab -Parameters @{ Text = $Text } {
            $parser = New-IslFilterParser -Rule $Text
            $node = Read-IslFilterExpression -Parser $parser
            [pscustomobject]@{ Node = $node; Error = $parser.Error; Pos = $parser.Pos }
        }
    }
}

Describe 'Read-IslFilterExpression' -Tag 'Unit', 'Private' {

    It 'binds and tighter than or' {
        $text = 'device.deviceName -eq "A" or device.model -eq "B" and device.manufacturer -eq "C"'
        $node = (Read-Expression -Text $text).Node

        $node['Type'] | Should-Be 'Or'
        $node['Left']['Clause'].Property | Should-Be 'deviceName'
        $node['Right']['Type'] | Should-Be 'And'
    }

    It 'joins several or groups from the left' {
        $text = 'device.deviceName -eq "A" -or device.model -eq "B" OR device.manufacturer -eq "C"'
        $node = (Read-Expression -Text $text).Node

        $node['Type'] | Should-Be 'Or'
        $node['Left']['Type'] | Should-Be 'Or'
        $node['Right']['Clause'].Property | Should-Be 'manufacturer'
    }

    It 'leaves a token that is no connector for the caller' {
        $result = Read-Expression -Text '(device.deviceName -eq "A") (device.model -eq "B")'

        $result.Error | Should-BeNull
        $result.Pos | Should-Be 5
    }

    It 'gives nothing when a group after or does not parse' {
        $result = Read-Expression -Text 'device.deviceName -eq "A" or ('

        $result.Error | Should-BeLikeString '*expected a clause or "(" at the end of the rule'
        $result.Node | Should-BeNull
    }
}
