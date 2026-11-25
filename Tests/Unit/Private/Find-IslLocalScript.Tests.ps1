#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The local files that may hold one script of a tenant policy: a -Map entry, or the names.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    $script:Root = Join-Path $TestDrive 'scripts'
    foreach ($relative in 'Fix Widget\detect.ps1', 'Fix Widget\remediate.ps1', 'Set-Wallpaper.ps1',
        'Single\only.ps1', 'Pair\detect-a.ps1', 'Pair\detect-b.ps1') {
        $full = Join-Path $script:Root $relative
        $null = New-Item -ItemType Directory -Path (Split-Path $full -Parent) -Force
        Set-Content -LiteralPath $full -Value 'exit 0' -Encoding ascii
    }

    function script:Find-Script {
        <#
        .SYNOPSIS
            Gets the sorted full paths of the local scripts that may hold a policy's script.

        .DESCRIPTION
            Runs Find-IslLocalScript inside the module for a policy of the given name, over every
            file and folder of the fixture tree under TestDrive, and returns the full path of each
            candidate it finds, sorted.

        .PARAMETER PolicyName
            The display name of the policy.

        .PARAMETER Role
            The role of the script in the policy: detection, remediation or script.

        .PARAMETER Pattern
            The pattern that the file name of the script matches. Left out, none is passed.

        .PARAMETER Map
            The -Map entries that name the local file of a policy.

        .EXAMPLE
            Find-Script -PolicyName 'Fix Widget' -Role 'detection' -Pattern '^(?i)detect'

            Returns the path of the detection script in the folder Fix Widget.

        .INPUTS
            None.

        .OUTPUTS
            System.String. The full path of each candidate.
        #>
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [string]$PolicyName,

            [string]$Role,

            [string]$Pattern,

            [hashtable]$Map
        )

        $parameters = @{
            Policy = @{ id = 'p1'; displayName = $PolicyName }; Role = $Role; Root = $script:Root
            LocalFile = @(Get-ChildItem -LiteralPath $script:Root -Recurse -File -Filter '*.ps1')
            LocalFolder = @(Get-Item -LiteralPath $script:Root) +
            @(Get-ChildItem -LiteralPath $script:Root -Recurse -Directory)
            Map = $Map; Matched = @{}
        }
        if ($Pattern) { $parameters['Pattern'] = $Pattern }
        InModuleScope IntuneScriptLab -Parameters @{ Parameters = $parameters } {
            @(Find-IslLocalScript @Parameters | ForEach-Object { $_.FullName } | Sort-Object)
        }
    }
}

Describe 'Find-IslLocalScript' -Tag 'Unit', 'Private' {

    Context 'By name' {
        It 'finds the <Role> script in the folder named after the policy by its pattern' -ForEach @(
            @{ Role = 'detection'; Pattern = '^(?i)detect'; Expected = 'detect.ps1' }
            @{ Role = 'remediation'; Pattern = '^(?i)remediat'; Expected = 'remediate.ps1' }
        ) {
            $found = @(Find-Script -PolicyName 'Fix Widget' -Role $Role -Pattern $Pattern)

            $found | Should-BeCollection -Count 1
            $found[0] | Should-Be (Join-Path $script:Root "Fix Widget\$Expected")
        }

        It 'finds the file named after a policy without a pattern' {
            $found = @(Find-Script -PolicyName 'Set-Wallpaper' -Role 'script')

            $found | Should-BeCollection @((Join-Path $script:Root 'Set-Wallpaper.ps1'))
        }

        It 'finds the single script in the folder named after the policy' {
            $expected = Join-Path $script:Root 'Single\only.ps1'
            Find-Script -PolicyName 'Single' -Role 'script' | Should-BeCollection @($expected)
        }

        It 'finds every match of the pattern, which the caller reports as ambiguous' {
            $found = @(Find-Script -PolicyName 'Pair' -Role 'detection' -Pattern '^(?i)detect')
            $found | Should-BeCollection -Count 2
        }

        It 'finds nothing for a policy without a folder or file of its name' {
            Find-Script -PolicyName 'Unknown' -Role 'script' | Should-BeCollection @()
        }
    }

    Context 'By -Map' {
        It 'takes a path entry for the detection script, under the root' {
            $map = @{ 'Fix Widget' = 'Single\only.ps1' }
            $found = @(Find-Script -PolicyName 'Fix Widget' -Role 'detection' -Map $map)

            $found | Should-BeCollection @((Join-Path $script:Root 'Single\only.ps1'))
        }

        It 'takes the role of a hashtable entry, and nothing for a role it leaves out' {
            $map = @{ 'Fix Widget' = @{ remediation = 'Pair\detect-b.ps1' } }

            Find-Script -PolicyName 'Fix Widget' -Role 'remediation' -Map $map |
                Should-BeCollection @((Join-Path $script:Root 'Pair\detect-b.ps1'))
            Find-Script -PolicyName 'Fix Widget' -Role 'detection' -Map $map | Should-BeCollection @()
        }

        It 'takes a rooted path as it is' {
            $elsewhere = Join-Path $TestDrive 'elsewhere.ps1'

            Find-Script -PolicyName 'Set-Wallpaper' -Role 'script' -Map @{ 'Set-Wallpaper' = $elsewhere } |
                Should-BeCollection @($elsewhere)
        }
    }
}
