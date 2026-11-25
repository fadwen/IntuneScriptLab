#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The assignment filter token at the parser's cursor.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }

    function script:Get-Token {
        param([string]$Rule, [int]$Position)
        InModuleScope IntuneScriptLab -Parameters @{ Rule = $Rule; Position = $Position } {
            $parser = New-IslFilterParser -Rule $Rule
            $parser.Pos = $Position
            @(Get-IslFilterToken -Parser $parser)
            # The cursor stays where it was
            $parser.Pos
        }
    }
}

Describe 'Get-IslFilterToken' -Tag 'Unit', 'Private' {

    It 'gives the token at the cursor without moving it' {
        $output = @(Get-Token -Rule '(device.deviceName -eq "X")' -Position 2)

        $output | Should-BeCollection -Count 2
        $output[0].Type | Should-Be 'word'
        $output[0].Text | Should-Be '-eq'
        $output[1] | Should-Be 2
    }

    It 'gives nothing when the cursor is past the last token' {
        $output = @(Get-Token -Rule '(device.deviceName -eq "X")' -Position 5)

        $output | Should-BeCollection -Count 1
        $output[0] | Should-Be 5
    }
}
