#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The exclude-mode note on a filter parser warning: a clause that never matches excludes nobody
    and one that matches every device excludes everybody (W32-FILTER-INCLUDE, W32-FILTER-EXCLUDE);
    include mode and the other warning kinds are passed through unchanged.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    function script:Get-Message {
        <#
        .SYNOPSIS
            Gets the message of a filter warning of a given kind for a given mode.

        .DESCRIPTION
            Builds a parser warning of the kind, with a fixed message about the clause at character
            29, and calls Get-IslFilterWarningMessage inside the module with it.

        .PARAMETER Kind
            The kind of the warning.

        .PARAMETER Mode
            The mode the filter is used in, such as Exclude.

        .EXAMPLE
            Get-Message -Kind $Kind -Mode Exclude

            Returns the text of the warning for a filter used to exclude devices.

        .INPUTS
            None.

        .OUTPUTS
            System.String. The text of the warning.
        #>
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [string]$Kind,

            [string]$Mode
        )

        $warning = [pscustomobject]@{ Kind = $Kind; Message = 'the clause at character 29 never matches' }
        InModuleScope IntuneScriptLab -Parameters @{ Warning = $warning; Mode = $Mode } {
            Get-IslFilterWarningMessage -Warning $Warning -Mode $Mode
        }
    }
}

Describe 'Get-IslFilterWarningMessage' -Tag 'Unit', 'Private' {

    It 'appends what a <Kind> clause does to an exclude filter' -ForEach @(
        @{ Kind = 'NeverMatches'
            Expected = '*never matches; as an exclude filter it excludes nobody, so the assignment reaches*'
        }
        @{ Kind = 'AlwaysMatches'
            Expected = '*as an exclude filter it excludes every device, so the assignment reaches nobody'
        }
    ) {
        Get-Message -Kind $Kind -Mode Exclude | Should-BeLikeString $Expected
    }

    It 'passes a <Kind> warning through unchanged in <Mode> mode' -ForEach @(
        @{ Kind = 'NeverMatches'; Mode = 'Include' }
        @{ Kind = 'AlwaysMatches'; Mode = 'Include' }
        @{ Kind = 'Deprecated'; Mode = 'Exclude' }
        @{ Kind = 'Undocumented'; Mode = 'Exclude' }
    ) {
        Get-Message -Kind $Kind -Mode $Mode | Should-Be 'the clause at character 29 never matches'
    }
}
