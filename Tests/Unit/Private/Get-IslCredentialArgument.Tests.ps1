#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    What a Get-Credential call is handed as its credential, for the interactive-call rule.
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
            ConvertTo-Ast 'Get-Credential -Credential $saved'

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

    function script:Get-Argument {
        <#
        .SYNOPSIS
            Gets the text of what the first command of a script is handed as its credential.

        .DESCRIPTION
            Finds the first command in the script and runs Get-IslCredentialArgument inside the
            module on it, returning the extent text of each argument it gives.

        .PARAMETER Text
            The text of a script whose first command is a Get-Credential call.

        .EXAMPLE
            Get-Argument -Text 'Get-Credential -Credential $saved'

            Returns '$saved'.

        .INPUTS
            None.

        .OUTPUTS
            System.String. The text of each credential argument.
        #>
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [string]$Text
        )

        $commandType = [System.Management.Automation.Language.CommandAst]
        $command = (ConvertTo-Ast $Text).Find({ param($node) $node -is $commandType }, $true)
        InModuleScope IntuneScriptLab -Parameters @{ Command = $command } {
            @(Get-IslCredentialArgument -Command $Command | ForEach-Object { $_.Extent.Text })
        }
    }
}

Describe 'Get-IslCredentialArgument' -Tag 'Unit', 'Private' {

    It 'gives <Expected> for <Text>' -ForEach @(
        @{ Text = 'Get-Credential -Credential $saved'; Expected = '$saved' }
        @{ Text = 'Get-Credential -Cred $saved'; Expected = '$saved' }
        @{ Text = 'Get-Credential -Credential:$saved'; Expected = '$saved' }
        @{ Text = 'Get-Credential $saved'; Expected = '$saved' }
        @{ Text = "Get-Credential 'LAB\user'"; Expected = "'LAB\user'" }
    ) {
        $found = @(Get-Argument -Text $Text)

        $found | Should-BeCollection -Count 1
        $found[0] | Should-Be $Expected
    }

    It 'gives nothing for <Text>' -ForEach @(
        @{ Text = 'Get-Credential' }
        @{ Text = "Get-Credential -Message 'Sign in'" }
        @{ Text = "Get-Credential -UserName 'LAB\user'" }
        @{ Text = "Get-Credential -Title 'x' -Credential `$saved" }
    ) {
        Get-Argument -Text $Text | Should-BeCollection @()
    }
}
