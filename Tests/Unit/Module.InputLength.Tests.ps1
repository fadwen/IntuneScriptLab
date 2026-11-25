#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    SEC-16: text that names or identifies something is refused when it binds if it is longer than
    1,000 characters. An assignment filter rule may be as long as the service takes, 3,072
    characters (FLT-X11, FLT-X12). Paths are left out on purpose: Windows accepts far longer ones
    (docs/StandardsDecisions.md).
#>

BeforeDiscovery {
    $script:Limited = @(
        @{ Command = 'Compare-IntuneDeployedScript'; Parameter = 'Name'; Limit = 1000 }
        @{ Command = 'Compare-IntuneDeployedScript'; Parameter = 'Id'; Limit = 1000 }
        @{ Command = 'Get-IntuneAgentLog'; Parameter = 'Id'; Limit = 1000 }
        @{ Command = 'Get-IntuneAgentTimeline'; Parameter = 'Id'; Limit = 1000 }
        @{ Command = 'Get-IntuneScriptHealth'; Parameter = 'Name'; Limit = 1000 }
        @{ Command = 'Get-IntuneScriptHealth'; Parameter = 'Id'; Limit = 1000 }
        @{ Command = 'Repair-IntuneScript'; Parameter = 'IncludeRule'; Limit = 1000 }
        @{ Command = 'Repair-IntuneScript'; Parameter = 'ExcludeRule'; Limit = 1000 }
        @{ Command = 'Test-IntuneDeployedScript'; Parameter = 'Name'; Limit = 1000 }
        @{ Command = 'Test-IntuneDeployedScript'; Parameter = 'Id'; Limit = 1000 }
        @{ Command = 'Test-IntuneDeployedScript'; Parameter = 'IncludeRule'; Limit = 1000 }
        @{ Command = 'Test-IntuneDeployedScript'; Parameter = 'ExcludeRule'; Limit = 1000 }
        @{ Command = 'Test-IntuneScript'; Parameter = 'IncludeRule'; Limit = 1000 }
        @{ Command = 'Test-IntuneScript'; Parameter = 'ExcludeRule'; Limit = 1000 }
        @{ Command = 'Test-IntuneAssignmentFilter'; Parameter = 'Rule'; Limit = 3072 }
    )
}

BeforeAll {
    $script:ModuleRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module -Name (Join-Path -Path $script:ModuleRoot -ChildPath 'IntuneScriptLab.psd1') -Force
    }
}

Describe 'Length of text parameters' -Tag 'Unit', 'Contract' {

    It '<Command> -<Parameter> allows <Limit> characters' -ForEach $script:Limited {
        $attribute = (Get-Command -Name $Command).Parameters[$Parameter].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateLengthAttribute] }

        @($attribute) | Should-BeCollection -Count 1
        $attribute.MaxLength | Should-Be $Limit
    }

    It '<Command> -<Parameter> refuses one character more when it binds' -ForEach $script:Limited {
        $splat = @{ $Parameter = 'a' * ($Limit + 1) }

        { & $Command @splat } | Should-Throw -FullyQualifiedErrorId "ParameterArgumentValidationError,$Command"
    }

    It 'takes an assignment filter rule of the 3,072 characters the service takes' {
        $rule = '(device.deviceName -eq "' + ('a' * 3046) + '")'

        $result = Test-IntuneAssignmentFilter -Rule $rule -SyntaxOnly -ErrorAction Stop

        $rule.Length | Should-Be 3072
        $result.Reason | Should-BeLikeString 'The rule is valid*'
    }
}
