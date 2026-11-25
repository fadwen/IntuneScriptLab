#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Path expansion for file rules: the 64-bit context by default, the 32-bit one with
    check32BitOn64System (W32-FILE-PF-32 found a Program Files (x86)-only file, W32-FILE-PF-64 did not).
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    function Resolve-RulePath {
        <#
        .SYNOPSIS
            Resolves the path of a Win32 app rule with the module's private function.

        .DESCRIPTION
            Calls Resolve-IslRulePath inside the module, where the private function is visible,
            and passes -Check32 on as its -Check32BitOn64System switch.

        .PARAMETER Path
            The path as the rule states it, with any environment variables.

        .PARAMETER Check32
            Resolves the path as a rule with Check32BitOn64System does.

        .EXAMPLE
            Resolve-RulePath '%ProgramFiles%\Vendor' -Check32

            Returns the path under Program Files (x86).

        .INPUTS
            None.

        .OUTPUTS
            System.String. The resolved path.
        #>
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [string]$Path,

            [switch]$Check32
        )

        InModuleScope IntuneScriptLab -Parameters @{ Path = $Path; Check32 = [bool]$Check32 } {
            Resolve-IslRulePath -Path $Path -Check32BitOn64System:$Check32
        }
    }
}

Describe 'Resolve-IslRulePath' -Tag 'Unit', 'Private' {

    It 'expands %ProgramFiles% to the 64-bit folder by default' {
        Resolve-RulePath '%ProgramFiles%\Vendor' | Should-Be (Join-Path $env:ProgramFiles 'Vendor')
    }

    It 'expands %ProgramFiles% and %CommonProgramFiles% to the (x86) folders in the 32-bit context' -Skip:(
        -not [Environment]::Is64BitOperatingSystem) {
        Resolve-RulePath '%ProgramFiles%\Vendor' -Check32 | Should-Be (Join-Path ${env:ProgramFiles(x86)} 'Vendor')
        Resolve-RulePath '%CommonProgramFiles%\X' -Check32 |
            Should-Be (Join-Path ${env:CommonProgramFiles(x86)} 'X')
    }

    It 'expands other variables the same in both contexts, case-insensitively' {
        Resolve-RulePath '%WINDIR%\System32' | Should-Be (Join-Path $env:WINDIR 'System32')
        Resolve-RulePath '%windir%\System32' -Check32 | Should-Be (Join-Path $env:WINDIR 'System32')
    }

    It 'leaves a literal path alone' {
        Resolve-RulePath 'C:\ProgramData\App' -Check32 | Should-Be 'C:\ProgramData\App'
    }
}
