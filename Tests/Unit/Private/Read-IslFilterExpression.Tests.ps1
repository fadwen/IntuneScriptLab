#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    A whole assignment filter expression: groups of and-joined clauses joined by or.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    function script:Read-Expression {
        <#
        .SYNOPSIS
            Reads a filter expression and returns its tree with the parser's final state.

        .DESCRIPTION
            Creates a parser for the text inside the module and reads one expression with the
            private Read-IslFilterExpression. The parser's error and position are returned with
            the tree, because the tests check where reading stopped as well as what it read.

        .PARAMETER Text
            The text of the filter rule.

        .EXAMPLE
            Read-Expression -Text '(device.deviceName -eq "A") or (device.model -eq "B")'

            Returns the tree of an or of two clauses, with no error.

        .INPUTS
            None.

        .OUTPUTS
            IntuneScriptLab.Test.ParsedExpression. An object with Node, Error and Pos.
        #>
        [CmdletBinding()]
        [OutputType('IntuneScriptLab.Test.ParsedExpression')]
        param(
            [string]$Text
        )

        InModuleScope IntuneScriptLab -Parameters @{ Text = $Text } {
            $parser = New-IslFilterParser -Rule $Text
            $node = Read-IslFilterExpression -Parser $parser
            [pscustomobject]@{
                PSTypeName = 'IntuneScriptLab.Test.ParsedExpression'
                Node = $node
                Error = $parser.Error
                Pos = $parser.Pos
            }
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
