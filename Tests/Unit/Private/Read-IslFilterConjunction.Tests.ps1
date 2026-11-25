#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The clauses of an assignment filter rule that are joined by and.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    function script:Read-Conjunction {
        <#
        .SYNOPSIS
            Reads the and-joined clauses of a filter rule, with the parser's state.

        .DESCRIPTION
            Builds a parser for the rule, calls Read-IslFilterConjunction on it inside the module,
            and returns the node it read with the parser's Error and Pos, so that a test can tell
            where reading stopped and why.

        .PARAMETER Text
            The text of the assignment filter rule.

        .EXAMPLE
            Read-Conjunction -Text 'device.deviceName -eq "A" or device.model -eq "B"'

            Returns the node of the clause before the or, with the state of the parser.

        .INPUTS
            None.

        .OUTPUTS
            IntuneScriptLab.Test.ConjunctionRead. Node, Error and Pos.
        #>
        [CmdletBinding()]
        [OutputType('IntuneScriptLab.Test.ConjunctionRead')]
        param(
            [string]$Text
        )

        InModuleScope IntuneScriptLab -Parameters @{ Text = $Text } {
            $parser = New-IslFilterParser -Rule $Text
            $node = Read-IslFilterConjunction -Parser $parser
            [pscustomobject]@{
                PSTypeName = 'IntuneScriptLab.Test.ConjunctionRead'
                Node = $node
                Error = $parser.Error
                Pos = $parser.Pos
            }
        }
    }
}

Describe 'Read-IslFilterConjunction' -Tag 'Unit', 'Private' {

    It 'joins three clauses from the left into And nodes' {
        $text = 'device.deviceName -eq "A" and device.model -eq "B" -AND device.manufacturer -eq "C"'
        $node = (Read-Conjunction -Text $text).Node

        $node['Type'] | Should-Be 'And'
        $node['Right']['Clause'].Property | Should-Be 'manufacturer'
        $node['Left']['Type'] | Should-Be 'And'
        $node['Left']['Left']['Clause'].Property | Should-Be 'deviceName'
        $node['Left']['Right']['Clause'].Property | Should-Be 'model'
    }

    It 'stops before or, which binds looser' {
        $result = Read-Conjunction -Text 'device.deviceName -eq "A" or device.model -eq "B"'

        $result.Node['Type'] | Should-Be 'Clause'
        $result.Pos | Should-Be 3
    }

    It 'gives nothing when a clause after and does not parse' {
        $result = Read-Conjunction -Text 'device.deviceName -eq "A" and device.color -eq "B"'

        $result.Error | Should-BeLikeString '*unknown property device.color*'
        $result.Node | Should-BeNull
    }
}
