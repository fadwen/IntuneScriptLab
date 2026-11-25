#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    A clause, or an expression in parentheses, of an assignment filter rule.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    function script:Read-Primary {
        param([string]$Text)
        InModuleScope IntuneScriptLab -Parameters @{ Text = $Text } {
            $parser = New-IslFilterParser -Rule $Text
            # An empty rule is refused before anything is read; the case is the end of the tokens
            if (-not $Text) { $parser.Error = $null }
            $node = Read-IslFilterPrimary -Parser $parser
            [pscustomobject]@{ Node = $node; Error = $parser.Error; Pos = $parser.Pos }
        }
    }
}

Describe 'Read-IslFilterPrimary' -Tag 'Unit', 'Private' {

    Context 'Core Functionality' {
        It 'reads a clause without parentheses' {
            $result = Read-Primary -Text 'device.deviceName -eq "X"'

            $result.Error | Should-BeNull
            $result.Node['Type'] | Should-Be 'Clause'
        }

        It 'reads the expression in parentheses and moves past the closing one' {
            $result = Read-Primary -Text '((device.deviceName -eq "X") or (device.model -eq "Y"))'

            $result.Error | Should-BeNull
            $result.Node['Type'] | Should-Be 'Or'
            $result.Pos | Should-Be 13
        }
    }

    Context 'Error Handling' {
        It 'refuses <Text>: <Reason>' -ForEach @(
            @{ Text = ''; Reason = '*expected a clause or "(" at the end of the rule' }
            @{ Text = ')'; Reason = "*unexpected ')' at position 1" }
            @{ Text = '(device.deviceName -eq "X"'; Reason = "*the '(' at position 1 is not closed" }
            @{ Text = '(device.deviceName -eq "X" "Y")'; Reason = "*expected 'and', 'or' or ')'*found 'Y'" }
            @{ Text = '(device.deviceName -eq "a\"b\"")'; Reason = '*cannot be escaped*' }
        ) {
            $result = Read-Primary -Text $Text

            $result.Error | Should-BeLikeString $Reason
            $result.Node | Should-BeNull
        }
    }
}
