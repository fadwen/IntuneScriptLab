#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The tree of a parsed assignment filter rule against the facts of a device.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    function script:Test-Tree {
        <#
        .SYNOPSIS
            Tests a filter rule against fixed device facts and returns each clause's result.

        .DESCRIPTION
            Parses the rule inside the module and runs Test-IslFilterNode on its tree against a
            device named LAB-PC-01 from Microsoft Corporation. Returns the verdict of the whole
            rule and the Matched value that each clause recorded, in the order of the clauses.

        .PARAMETER Rule
            The text of the filter rule.

        .EXAMPLE
            Test-Tree -Rule '(device.deviceName -eq "LAB-PC-01")'

            Returns a verdict of True with one clause that matched.

        .INPUTS
            None.

        .OUTPUTS
            IntuneScriptLab.Test.FilterTreeResult. Matched and Clauses.
        #>
        [CmdletBinding()]
        [OutputType('IntuneScriptLab.Test.FilterTreeResult')]
        param(
            [string]$Rule
        )

        InModuleScope IntuneScriptLab -Parameters @{ Rule = $Rule } {
            $facts = [System.Collections.Generic.Dictionary[string, object]]::new(
                [System.StringComparer]::OrdinalIgnoreCase)
            $facts['deviceName'] = 'LAB-PC-01'
            $facts['manufacturer'] = 'Microsoft Corporation'
            $parsed = ConvertFrom-IslFilterRule -Rule $Rule
            $matched = Test-IslFilterNode -Node $parsed.Tree -Facts $facts
            [pscustomobject]@{
                PSTypeName = 'IntuneScriptLab.Test.FilterTreeResult'
                Matched = $matched
                Clauses = @($parsed.Clauses | ForEach-Object { $_.Matched })
            }
        }
    }
}

Describe 'Test-IslFilterNode' -Tag 'Unit', 'Private' {

    It 'gives <Expected> for <Rule>' -ForEach @(
        @{ Rule = '(device.deviceName -eq "LAB-PC-01")'; Expected = $true }
        @{ Rule = '(device.deviceName -eq "LAB-PC-01") and (device.manufacturer -eq "Dell")'; Expected = $false }
        @{ Rule = '(device.deviceName -eq "X") or (device.manufacturer -startsWith "Micro")'; Expected = $true }
        @{ Rule = '(device.deviceName -eq "X") or (device.manufacturer -eq "Dell")'; Expected = $false }
    ) {
        (Test-Tree -Rule $Rule).Matched | Should-Be $Expected
    }

    It 'tests both sides of and, so every clause records what it saw' {
        $result = Test-Tree -Rule '(device.deviceName -eq "X") and (device.manufacturer -startsWith "Microsoft")'

        $result.Matched | Should-BeFalse
        $result.Clauses | Should-BeCollection -Count 2
        $result.Clauses[0] | Should-BeFalse
        $result.Clauses[1] | Should-BeTrue
    }

    It 'tests both sides of or as well' {
        $result = Test-Tree -Rule '(device.deviceName -eq "LAB-PC-01") or (device.manufacturer -eq "Dell")'

        $result.Matched | Should-BeTrue
        $result.Clauses | Should-BeCollection -Count 2
        $result.Clauses[1] | Should-BeFalse
    }
}
