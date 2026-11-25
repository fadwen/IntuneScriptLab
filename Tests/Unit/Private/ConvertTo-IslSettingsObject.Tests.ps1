#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The validation of a settings table and the object the analysis reads from it. The search for
    the file is tested in Get-IslSetting.Tests.ps1.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    function ConvertTo-SettingsTable {
        param([hashtable]$Table, [string]$Source = '-Settings')
        $parameters = @{ Table = $Table; Source = $Source }
        $scope = @{ Parameters = $parameters }
        InModuleScope IntuneScriptLab -Parameters $scope { ConvertTo-IslSettingsObject @Parameters }
    }
}

Describe 'ConvertTo-IslSettingsObject' -Tag 'Unit', 'Private' {

    Context 'Parameter Validation' {
        It 'needs the table and its source' {
            $command = InModuleScope IntuneScriptLab { Get-Command -Name ConvertTo-IslSettingsObject }
            $command | Should-HaveParameter -ParameterName Table -Type ([hashtable]) -Mandatory
            $command | Should-HaveParameter -ParameterName Source -Type ([string]) -Mandatory
        }
    }

    Context 'Core Functionality' {
        It 'gives empty settings for an empty table' {
            $settings = ConvertTo-SettingsTable -Table @{} -Source ''

            $settings | Should-HaveType 'IntuneScriptLab.Settings'
            $settings.Source | Should-Be ''
            $settings.ExcludeRule | Should-BeCollection @()
            $settings.IncludeRule | Should-BeCollection @()
            $settings.MinimumSeverity | Should-BeNull
            $settings.Severity.Count | Should-Be 0
            $settings.ScriptType | Should-BeNull
            $settings.Context | Should-BeNull
            $settings.Architecture | Should-BeNull
            $settings.EnforceSignatureCheck | Should-BeNull
        }

        It 'carries every key that is given' {
            $settings = ConvertTo-SettingsTable -Table @{
                ExcludeRule = 'IslLongSleep', ''; IncludeRule = 'Isl*'; MinimumSeverity = 'Warning'
                Severity = @{ IslLongSleep = 'Error' }; ScriptType = 'Detection'; Context = 'User'
                Architecture = 'x64'; EnforceSignatureCheck = $false
            }

            $settings.ExcludeRule | Should-BeCollection @('IslLongSleep')
            $settings.IncludeRule | Should-BeCollection @('Isl*')
            $settings.MinimumSeverity | Should-Be 'Warning'
            $settings.Severity['IslLongSleep'] | Should-Be 'Error'
            $settings.ScriptType | Should-Be 'Detection'
            $settings.Context | Should-Be 'User'
            $settings.Architecture | Should-Be 'x64'
            $settings.EnforceSignatureCheck | Should-BeFalse
        }

        It 'names a key it does not know in a warning and still converts the table' {
            $output = InModuleScope IntuneScriptLab {
                ConvertTo-IslSettingsObject -Table @{ Severety = @{}; Context = 'User' } -Source 'x.psd1' 3>&1
            }
            $warnings = @($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
            $settings = @($output | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })

            $warnings | Should-BeCollection -Count 1
            "$($warnings[0])" | Should-Be 'Unknown settings key(s) in x.psd1: Severety'
            $settings | Should-BeCollection -Count 1
            $settings[0].Context | Should-Be 'User'
        }
    }

    Context 'Error Handling' {
        It 'refuses <Case> with SettingsInvalid, naming the source' -ForEach @(
            @{
                Case = 'a minimum severity outside the set'; Table = @{ MinimumSeverity = 'Fatal' }
                Text = '*MinimumSeverity must be one of*'
            }
            @{ Case = 'an unknown script type'; Table = @{ ScriptType = 'Script' }; Text = '*ScriptType must be*' }
            @{ Case = 'an unknown context'; Table = @{ Context = 'Admin' }; Text = '*Context must be System*' }
            @{ Case = 'an unknown architecture'; Table = @{ Architecture = 'ia64' }; Text = '*Architecture must*' }
            @{
                Case = 'a severity override outside the set'; Table = @{ Severity = @{ IslLongSleep = 'Loud' } }
                Text = '*Severity for IslLongSleep*'
            }
            @{
                Case = 'a severity that is not a hashtable'; Table = @{ Severity = 'Error' }
                Text = '*Severity must be a hashtable of rule names*'
            }
            @{
                Case = 'a severity that is a list'; Table = @{ Severity = @('IslLongSleep', 'Error') }
                Text = '*Severity must be a hashtable of rule names*'
            }
            @{
                Case = 'a severity of 0'; Table = @{ Severity = 0 }
                Text = '*Severity must be a hashtable of rule names*'
            }
            @{
                Case = 'a severity of $false'; Table = @{ Severity = $false }
                Text = '*Severity must be a hashtable of rule names*'
            }
            @{
                Case = 'a severity that is an empty text'; Table = @{ Severity = '' }
                Text = '*Severity must be a hashtable of rule names*'
            }
            @{
                Case = 'a severity that is an empty list'; Table = @{ Severity = @() }
                Text = '*Severity must be a hashtable of rule names*'
            }
        ) {
            $failure = { ConvertTo-SettingsTable -Table $Table -Source 'C:\repo\IntuneScriptLab.settings.psd1' } |
                Should-Throw -ExceptionMessage $Text
            $failure.FullyQualifiedErrorId | Should-BeLikeString 'SettingsInvalid,*'
            $failure.Exception.Message | Should-BeLikeString 'C:\repo\IntuneScriptLab.settings.psd1: *'
        }

        It 'names the first value that is wrong, in the order of the checks' {
            { ConvertTo-SettingsTable -Table @{ Context = 'Admin'; ScriptType = 'Script' } } |
                Should-Throw -ExceptionMessage '*ScriptType must be one of*'
        }
    }
}
