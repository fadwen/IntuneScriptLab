#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The assignment filter token at the parser's cursor.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    function script:Get-Token {
        <#
        .SYNOPSIS
            Gets the filter token at a cursor position, and the position after the call.

        .DESCRIPTION
            Builds a parser for the rule inside the module, puts its cursor on the position and runs
            the private Get-IslFilterToken. The position of the cursor after the call comes last, so
            that a test can check that reading the token did not move it.

        .PARAMETER Rule
            The text of the assignment filter rule.

        .PARAMETER Position
            The index of the token the cursor is put on.

        .EXAMPLE
            Get-Token -Rule '(device.deviceName -eq "X")' -Position 2

            Returns the token '-eq' and then 2.

        .INPUTS
            None.

        .OUTPUTS
            System.Object. The IntuneScriptLab.FilterToken, if there is one, then the cursor as an integer.
        #>
        [CmdletBinding()]
        [OutputType([object])]
        param(
            [string]$Rule,

            [int]$Position
        )

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
        $output[0] | Should-HaveType 'IntuneScriptLab.FilterToken'
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
