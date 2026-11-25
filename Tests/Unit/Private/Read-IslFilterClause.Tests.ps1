#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    One comparison of an assignment filter rule: its property, operator and value.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    function script:Read-Clause {
        param([string]$Text)
        InModuleScope IntuneScriptLab -Parameters @{ Text = $Text } {
            $parser = New-IslFilterParser -Rule $Text
            # An empty rule is refused before anything is read; the case is the end of the tokens
            if (-not $Text) { $parser.Error = $null }
            $node = Read-IslFilterClause -Parser $parser
            [pscustomobject]@{
                Node = $node; Error = $parser.Error; Clauses = $parser.Clauses.ToArray()
                Warnings = $parser.Warnings.ToArray(); Pos = $parser.Pos
            }
        }
    }
}

Describe 'Read-IslFilterClause' -Tag 'Unit', 'Private' {

    Context 'Core Functionality' {
        It 'reads a clause into a node, adds it to the clauses and moves past it' {
            $result = Read-Clause -Text 'device.DeviceName -EQ "LAB-PC-01" and'

            $result.Error | Should-BeNull
            $result.Node['Type'] | Should-Be 'Clause'
            $result.Clauses | Should-BeCollection -Count 1
            $clause = $result.Clauses[0]
            $clause | Should-HaveType 'IntuneScriptLab.FilterClause'
            $clause.Property | Should-Be 'deviceName'
            $clause.Kind | Should-Be 'String'
            $clause.Operator | Should-Be 'eq'
            $clause.Value | Should-Be 'LAB-PC-01'
            $clause.Text | Should-Be 'device.DeviceName -EQ "LAB-PC-01"'
            $clause.Position | Should-Be 1
            $result.Node['Clause'].Text | Should-Be $clause.Text
            $result.Pos | Should-Be 3
        }

        It 'warns about the <Kind> property <Text>' -ForEach @(
            @{ Text = 'device.osVersion -eq "10.0"'; Kind = 'Deprecated' }
            @{ Text = 'device.isTpmAttested -eq "True"'; Kind = 'Undocumented' }
        ) {
            $result = Read-Clause -Text $Text

            $result.Error | Should-BeNull
            @($result.Warnings | Where-Object { $_.Kind -eq $Kind }) | Should-BeCollection -Count 1
        }
    }

    Context 'Error Handling' {
        It 'refuses <Text>: <Reason>' -ForEach @(
            @{ Text = ''; Reason = '*expected a clause such as*at the end' }
            @{ Text = '"device.deviceName"'; Reason = '*expected a property such as device.deviceName*' }
            @{ Text = 'and'; Reason = "*expected a clause before 'and'*" }
            @{ Text = '-not'; Reason = "*'not' is not an operator the service accepts*" }
            @{ Text = 'deviceName -eq "X"'; Reason = '*is not a property; a clause starts with device.*' }
            @{ Text = 'app.appVersion -eq "1"'; Reason = '*is a managed app property*' }
            @{ Text = 'user.name -eq "X"'; Reason = "*unknown entity 'user'*" }
            @{ Text = 'device.color -eq "X"'; Reason = '*unknown property device.color*filters know:*' }
            @{ Text = 'device.deviceName'; Reason = '*operator after device.deviceName; the rule ends' }
            @{ Text = 'device.deviceName "X"'; Reason = "*operator after device.deviceName; found 'X'" }
            @{ Text = 'device.deviceName -endsWith "X"'; Reason = '*-endsWith is refused by the service*' }
            @{ Text = 'device.deviceName -like "X"'; Reason = "*unknown operator '-like'*" }
            @{ Text = 'device.deviceName -gt "X"'; Reason = '*-gt is not allowed on device.deviceName*' }
            @{ Text = 'device.deviceName -eq X'; Reason = '*must be in double quotes*' }
        ) {
            $result = Read-Clause -Text $Text

            $result.Error | Should-BeLikeString $Reason
            $result.Node | Should-BeNull
            $result.Clauses | Should-BeCollection @()
        }
    }
}
