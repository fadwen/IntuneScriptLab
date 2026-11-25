#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    One clause of an assignment filter against the facts of a device. The clauses are built by
    the module's own parser, as Test-IntuneAssignmentFilter builds them.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }

    # The first clause of a rule, its verdict, and the clause afterwards
    function script:Test-Rule {
        param([string]$Rule, [hashtable]$Device)
        InModuleScope IntuneScriptLab -Parameters @{ Rule = $Rule; Device = $Device } {
            $facts = [System.Collections.Generic.Dictionary[string, object]]::new(
                [System.StringComparer]::OrdinalIgnoreCase)
            foreach ($key in $Device.Keys) { $facts[$key] = $Device[$key] }
            $clause = @((ConvertFrom-IslFilterRule -Rule $Rule).Clauses)[0]
            $matched = Test-IslFilterClause -Clause $clause -Facts $facts
            [pscustomobject]@{ Matched = $matched; Clause = $clause }
        }
    }

    $script:Device = @{
        deviceName = 'LAB-PC-01'; operatingSystemVersion = '10.0.26100.4202'
        manufacturer = 'Microsoft Corporation'; operatingSystemSKU = 'Enterprise'
    }
}

Describe 'Test-IslFilterClause' -Tag 'Unit', 'Private' {

    Context 'Parameter Validation' {
        It 'takes only a filter clause' {
            $command = InModuleScope IntuneScriptLab { Get-Command -Name Test-IslFilterClause }
            $command | Should-HaveParameter -ParameterName Clause -Mandatory
            $command | Should-HaveParameter -ParameterName Facts -Mandatory
            $typeAttribute = [System.Management.Automation.PSTypeNameAttribute]
            $clauseType = @($command.Parameters['Clause'].Attributes | Where-Object { $_ -is $typeAttribute })
            $clauseType[0].PSTypeName | Should-Be 'IntuneScriptLab.FilterClause'
        }
    }

    Context 'Core Functionality' {
        It 'gives <Expected> for <Rule>' -ForEach @(
            @{ Rule = '(device.deviceName -eq "lab-pc-01")'; Expected = $true }
            @{ Rule = '(device.deviceName -ne "LAB-PC-01")'; Expected = $false }
            @{ Rule = '(device.deviceName -startsWith "lab-")'; Expected = $true }
            @{ Rule = '(device.manufacturer -contains "microsoft")'; Expected = $true }
            @{ Rule = '(device.manufacturer -notContains "Dell")'; Expected = $true }
            @{ Rule = '(device.operatingSystemSKU -in ["Education", "Enterprise"])'; Expected = $true }
            @{ Rule = '(device.operatingSystemSKU -notIn ["Education", "Enterprise"])'; Expected = $false }
            @{ Rule = '(device.operatingSystemVersion -ge 10.0.22000.1)'; Expected = $true }
            @{ Rule = '(device.operatingSystemVersion -lt 10.0.22000.1)'; Expected = $false }
            @{ Rule = '(device.operatingSystemVersion -eq 10.0.26100.4202)'; Expected = $true }
        ) {
            (Test-Rule -Rule $Rule -Device $script:Device).Matched | Should-Be $Expected
        }

        It 'records on the clause what the device had and whether it matched' {
            $result = Test-Rule -Rule '(device.deviceName -eq "OTHER")' -Device $script:Device

            $result.Clause.Actual | Should-Be 'LAB-PC-01'
            $result.Clause.Matched | Should-BeFalse
        }

        It 'compares a property the device does not have as an empty text, and records no value' {
            $result = Test-Rule -Rule '(device.deviceName -eq "LAB-PC-01")' -Device @{}

            $result.Matched | Should-BeFalse
            $result.Clause.Actual | Should-BeNull
        }

        It 'gives <Expected> for <Operator> when the device version is not a version' -ForEach @(
            @{ Operator = 'eq'; Expected = $false }
            @{ Operator = 'ne'; Expected = $true }
            @{ Operator = 'ge'; Expected = $false }
            @{ Operator = 'lt'; Expected = $false }
        ) {
            $device = @{ operatingSystemVersion = 'unknown' }
            $rule = "(device.operatingSystemVersion -$Operator 10.0.22000.1)"

            (Test-Rule -Rule $rule -Device $device).Matched | Should-Be $Expected
        }
    }
}
