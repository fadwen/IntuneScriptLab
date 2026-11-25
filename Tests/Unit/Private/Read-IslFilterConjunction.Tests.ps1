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
        param([string]$Text)
        InModuleScope IntuneScriptLab -Parameters @{ Text = $Text } {
            $parser = New-IslFilterParser -Rule $Text
            $node = Read-IslFilterConjunction -Parser $parser
            [pscustomobject]@{ Node = $node; Error = $parser.Error; Pos = $parser.Pos }
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
