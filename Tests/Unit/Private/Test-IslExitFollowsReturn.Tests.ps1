#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Whether an exit with another code follows a script-scope return, for the exit-code rule.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    function script:ConvertTo-Ast {
        <#
        .SYNOPSIS
            Converts the text of a script to its syntax tree.

        .DESCRIPTION
            Parses the text with the PowerShell parser and ignores its tokens and errors, so that a
            test can hand a node of the tree to the function under test.

        .PARAMETER Text
            The text of the script.

        .EXAMPLE
            ConvertTo-Ast "return 'ok'"

            Returns the syntax tree of the one-line script.

        .INPUTS
            None.

        .OUTPUTS
            System.Management.Automation.Language.ScriptBlockAst. The syntax tree of the script.
        #>
        [CmdletBinding()]
        [OutputType([System.Management.Automation.Language.ScriptBlockAst])]
        param(
            [string]$Text
        )

        [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null)
    }

    function script:Test-FollowingExit {
        <#
        .SYNOPSIS
            Tests whether an exit with another code follows the first return of a script.

        .DESCRIPTION
            Finds the first return statement in the script and runs Test-IslExitFollowsReturn
            inside the module on it.

        .PARAMETER Text
            The text of a script that holds a return statement.

        .EXAMPLE
            Test-FollowingExit -Text "return 'missing'`nexit 1"

            Returns True.

        .INPUTS
            None.

        .OUTPUTS
            System.Boolean. Whether such an exit follows the return.
        #>
        [CmdletBinding()]
        [OutputType([bool])]
        param(
            [string]$Text
        )

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
