#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The value after an operator in an assignment filter rule, checked against the property and the
    operator. The rule given to each case is only the value; the parser's cursor starts on it.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }

    # The value read, the failure, the warnings and where the cursor ended up
    function script:Read-Value {
        param([string]$Text, [string]$Property, [string]$Operator)
        InModuleScope IntuneScriptLab -Parameters @{ Text = $Text; Property = $Property; Operator = $Operator } {
            $parser = New-IslFilterParser -Rule $Text
            # An empty rule is refused before anything is read; the case is the end of the tokens
            if (-not $Text) { $parser.Error = $null }
            $valueSplat = @{ Parser = $parser; Property = $parser.Properties[$Property]; Operator = $Operator }
            $value = @(Read-IslFilterValue @valueSplat)
            [pscustomobject]@{
                Value = $value; Error = $parser.Error; Warnings = $parser.Warnings.ToArray(); Pos = $parser.Pos
            }
        }
    }
}

Describe 'Read-IslFilterValue' -Tag 'Unit', 'Private' {

    Context 'Core Functionality' {
        It 'reads <Text> for -<Operator> on <Property> as <Expected>' -ForEach @(
            @{ Text = '"LAB-PC-01"'; Property = 'devicename'; Operator = 'eq'; Expected = @('LAB-PC-01') }
            @{ Text = '["a", "b",]'; Property = 'osversion'; Operator = 'in'; Expected = @('a', 'b') }
            @{ Text = '10.0.22631'; Property = 'operatingsystemversion'; Operator = 'ge'; Expected = '10.0.22631' }
            @{
                Text = '"10.0.22631"'; Property = 'operatingsystemversion'; Operator = 'ge'; Expected = '10.0.22631'
            }
            @{ Text = '$null'; Property = 'devicename'; Operator = 'eq'; Expected = @($null) }
            @{ Text = 'null'; Property = 'devicename'; Operator = 'ne'; Expected = @($null) }
        ) {
            $result = Read-Value -Text $Text -Property $Property -Operator $Operator

            $result.Error | Should-BeNull
            $Expected = @($Expected)
            $result.Value | Should-BeCollection -Count $Expected.Count
            for ($index = 0; $index -lt $Expected.Count; $index++) {
                $result.Value[$index] | Should-Be $Expected[$index]
            }
        }

        It 'moves the cursor past the whole value' {
            (Read-Value -Text '["a", "b"] and' -Property 'osversion' -Operator 'in').Pos | Should-Be 5
        }

        It 'warns that a value outside the set <Expected> for -<Operator>' -ForEach @(
            @{ Operator = 'eq'; Expected = 'never matches' }
            @{ Operator = 'ne'; Expected = 'matches every device' }
        ) {
            $result = Read-Value -Text '"x64"' -Property 'cpuarchitecture' -Operator $Operator

            $result.Error | Should-BeNull
            $result.Warnings | Should-BeCollection -Count 1
            $result.Warnings[0].Message | Should-BeLikeString "'x64' is not a value*amd64, x86, arm64*$Expected"
        }

        It 'warns that -contains with only white space matches every device' {
            $result = Read-Value -Text '" "' -Property 'devicename' -Operator 'contains'

            $result.Warnings | Should-BeCollection -Count 1
            $result.Warnings[0].Kind | Should-Be 'AlwaysMatches'
        }

        It 'warns about nothing for a property without a set of values' {
            (Read-Value -Text '"X"' -Property 'devicename' -Operator 'eq').Warnings | Should-BeCollection @()
        }
    }

    Context 'Error Handling' {
        It 'refuses <Text> for -<Operator> on <Property>: <Reason>' -ForEach @(
            @{ Text = ''; Property = 'devicename'; Operator = 'eq'; Reason = '*value after -eq at the end*' }
            @{ Text = 'X'; Property = 'devicename'; Operator = 'eq'; Reason = '*X must be in double quotes*' }
            @{ Text = '10.0'; Property = 'devicename'; Operator = 'eq'; Reason = '*10.0 must be in double*' }
            @{ Text = '["a"'; Property = 'osversion'; Operator = 'in'; Reason = '*position 1 is not closed*' }
            @{ Text = '[a]'; Property = 'osversion'; Operator = 'in'; Reason = '*double-quoted strings only*' }
            @{ Text = '["a" "b"]'; Property = 'osversion'; Operator = 'in'; Reason = "*expected ',' or ']'*" }
            @{ Text = '["a\"b\""]'; Property = 'osversion'; Operator = 'in'; Reason = '*cannot be escaped*' }
            @{ Text = '[]'; Property = 'osversion'; Operator = 'in'; Reason = '*list at position 1 is empty*' }
            @{ Text = ','; Property = 'devicename'; Operator = 'eq'; Reason = "*found ','*" }
            @{ Text = '["a"]'; Property = 'devicename'; Operator = 'eq'; Reason = '*-eq takes a single value*' }
            @{ Text = '$null'; Property = 'devicename'; Operator = 'contains'; Reason = '*with -eq and -ne only*' }
            @{
                Text = '$null'; Property = 'operatingsystemversion'; Operator = 'eq'
                Reason = '*cannot be compared with $null*'
            }
            @{
                Text = '["10.0"]'; Property = 'operatingsystemversion'; Operator = 'in'
                Reason = '*takes a single version, not a list*'
            }
            @{
                Text = '"10"'; Property = 'operatingsystemversion'; Operator = 'ge'
                Reason = "*'10' is not a version of 2 to 4 numeric parts*"
            }
            @{ Text = '""'; Property = 'devicename'; Operator = 'eq'; Reason = '*an empty string is refused*' }
        ) {
            $result = Read-Value -Text $Text -Property $Property -Operator $Operator

            $result.Error | Should-BeLikeString $Reason
            $result.Value | Should-BeCollection @()
        }
    }
}
