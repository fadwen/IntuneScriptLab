#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Whether an exit with another code follows a script-scope return, for the exit-code rule.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }

    # The syntax tree of a script given as text
    function script:ConvertTo-Ast {
        param([string]$Text)
        [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null)
    }

    function script:Test-FollowingExit {
        param([string]$Text)
        $return = (ConvertTo-Ast $Text).Find({
                param($node) $node -is [System.Management.Automation.Language.ReturnStatementAst]
            }, $true)
        InModuleScope IntuneScriptLab -Parameters @{ Return = $return } {
            Test-IslExitFollowsReturn -Return $Return
        }
    }
}

Describe 'Test-IslExitFollowsReturn' -Tag 'Unit', 'Private' {

    It 'gives <Expected> for <Case>' -ForEach @(
        @{ Case = 'an exit 1 after the return'; Text = "return 'missing'`nexit 1"; Expected = $true }
        @{ Case = 'an exit 0 after the return'; Text = "return 'ok'`nexit 0"; Expected = $false }
        @{ Case = 'an exit 1 before the return'; Text = "exit 1`nreturn 'ok'"; Expected = $false }
        @{ Case = 'no exit at all'; Text = "return 'ok'"; Expected = $false }
        @{ Case = 'an exit in another block'; Text = "if (`$a) { return 'ok' }`nexit 1"; Expected = $false }
    ) {
        Test-FollowingExit -Text $Text | Should-Be $Expected
    }
}
