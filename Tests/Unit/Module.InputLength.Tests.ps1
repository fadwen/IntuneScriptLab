#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    SEC-16: text that names or identifies something is refused when it is longer than 1,000
    characters. The optional parameters check it in the body, because [ValidateLength()] would
    also refuse $null, which they take to mean "not given". An assignment filter rule may be as
    long as the service takes, 3,072 characters (FLT-X11, FLT-X12), and is mandatory, so it keeps
    the attribute. Paths are left out on purpose: Windows accepts far longer ones
    (docs/StandardsDecisions.md).
#>

BeforeDiscovery {
    $script:Limited = @(
        @{ Command = 'Compare-IntuneDeployedScript'; Parameter = 'Name' }
        @{ Command = 'Compare-IntuneDeployedScript'; Parameter = 'Id' }
        @{ Command = 'Get-IntuneAgentLog'; Parameter = 'Id' }
        @{ Command = 'Get-IntuneAgentTimeline'; Parameter = 'Id' }
        @{ Command = 'Get-IntuneScriptHealth'; Parameter = 'Name' }
        @{ Command = 'Get-IntuneScriptHealth'; Parameter = 'Id' }
        @{ Command = 'Repair-IntuneScript'; Parameter = 'IncludeRule' }
        @{ Command = 'Repair-IntuneScript'; Parameter = 'ExcludeRule' }
        @{ Command = 'Test-IntuneDeployedScript'; Parameter = 'Name' }
        @{ Command = 'Test-IntuneDeployedScript'; Parameter = 'Id' }
        @{ Command = 'Test-IntuneDeployedScript'; Parameter = 'IncludeRule' }
        @{ Command = 'Test-IntuneDeployedScript'; Parameter = 'ExcludeRule' }
        @{ Command = 'Test-IntuneScript'; Parameter = 'IncludeRule' }
        @{ Command = 'Test-IntuneScript'; Parameter = 'ExcludeRule' }
    )
}

BeforeAll {
    $script:ModuleRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module -Name (Join-Path -Path $script:ModuleRoot -ChildPath 'IntuneScriptLab.psd1') -Force
    }
}

Describe 'Length of text parameters' -Tag 'Unit', 'Contract', 'Security' {

    Context 'Optional names, ids and rule names' {
        It '<Command> -<Parameter> refuses 1,001 characters before it does anything' -ForEach $script:Limited {
            $splat = @{ $Parameter = 'a' * 1001 }
            # A mandatory -Path is given, so that the check, not the binding, answers
            if ((Get-Command -Name $Command).Parameters['Path'].Attributes.Mandatory -contains $true) {
                $splat['Path'] = $TestDrive
            }

            { & $Command @splat -ErrorAction Stop } | Should-Throw -FullyQualifiedErrorId "InputTooLong,$Command"
        }

        It '<Command> -<Parameter> has no attribute that would refuse $null' -ForEach $script:Limited {
            $attributes = (Get-Command -Name $Command).Parameters[$Parameter].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateArgumentsAttribute] }

            @($attributes) | Should-BeCollection @()
        }

        It 'takes $null, and a value of 1,000 characters, as an id' {
            $logs = Join-Path -Path $TestDrive -ChildPath 'no-logs'
            $null = New-Item -ItemType Directory -Path $logs

            # -ErrorAction Stop makes any error, a refusal at binding among them, fail the test
            $timelineSplat = @{ Path = $logs; WarningAction = 'SilentlyContinue'; ErrorAction = 'Stop' }
            $none = @(Get-IntuneAgentTimeline -Id $null @timelineSplat)
            $longest = @(Get-IntuneAgentTimeline -Id ('a' * 1000) @timelineSplat)

            $none | Should-BeCollection @()
            $longest | Should-BeCollection @()
        }
    }

    Context 'Assignment filter rule' {
        It 'allows the 3,072 characters the service takes, and refuses one more when it binds' {
            $attribute = (Get-Command -Name Test-IntuneAssignmentFilter).Parameters['Rule'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateLengthAttribute] }
            $longest = '(device.deviceName -eq "' + ('a' * 3046) + '")'

            $attribute.MaxLength | Should-Be 3072
            (Test-IntuneAssignmentFilter -Rule $longest -SyntaxOnly -ErrorAction Stop).Reason |
                Should-BeLikeString 'The rule is valid*'
            { Test-IntuneAssignmentFilter -Rule ($longest + ' ') -SyntaxOnly } |
                Should-Throw -FullyQualifiedErrorId 'ParameterArgumentValidationError,Test-IntuneAssignmentFilter'
        }
    }
}
