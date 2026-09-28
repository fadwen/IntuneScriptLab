#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Path expansion for file rules: the 64-bit context by default, the 32-bit one with
    check32BitOn64System (W32-FILE-PF-32 found a Program Files (x86)-only file, W32-FILE-PF-64 did not).
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force

    function Resolve-RulePath {
        param([string]$Path, [bool]$Check32 = $false)
        InModuleScope IntuneScriptLab -Parameters @{ Path = $Path; Check32 = $Check32 } {
            Resolve-IslRulePath -Path $Path -Check32BitOn64System $Check32
        }
    }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Resolve-IslRulePath' -Tag 'Unit', 'Private' {

    It 'expands %ProgramFiles% to the 64-bit folder by default' {
        Resolve-RulePath '%ProgramFiles%\Vendor' | Should-Be (Join-Path $env:ProgramFiles 'Vendor')
    }

    It 'expands %ProgramFiles% and %CommonProgramFiles% to the (x86) folders in the 32-bit context' -Skip:(
        -not [Environment]::Is64BitOperatingSystem) {
        Resolve-RulePath '%ProgramFiles%\Vendor' $true | Should-Be (Join-Path ${env:ProgramFiles(x86)} 'Vendor')
        Resolve-RulePath '%CommonProgramFiles%\X' $true | Should-Be (Join-Path ${env:CommonProgramFiles(x86)} 'X')
    }

    It 'expands other variables the same in both contexts, case-insensitively' {
        Resolve-RulePath '%WINDIR%\System32' | Should-Be (Join-Path $env:WINDIR 'System32')
        Resolve-RulePath '%windir%\System32' $true | Should-Be (Join-Path $env:WINDIR 'System32')
    }

    It 'leaves a literal path alone' {
        Resolve-RulePath 'C:\ProgramData\App' $true | Should-Be 'C:\ProgramData\App'
    }
}
