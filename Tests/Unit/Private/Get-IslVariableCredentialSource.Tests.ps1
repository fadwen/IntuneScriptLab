#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    How a variable comes to hold a credential, for the interactive-call rule.
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
            test can hand the tree and a node of it to the function under test.

        .PARAMETER Text
            The text of the script.

        .EXAMPLE
            ConvertTo-Ast 'Get-Credential -Credential $cred'

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

    function script:Get-Source {
        <#
        .SYNOPSIS
            Gets the source of the variable that Get-Credential is handed in a script.

        .DESCRIPTION
            Finds the first Get-Credential call in the script, takes its last element as the
            variable and runs Get-IslVariableCredentialSource inside the module on it.

        .PARAMETER Text
            The text of a script that calls Get-Credential with a variable as its last argument.

        .EXAMPLE
            Get-Source -Text "`$cred = Import-Clixml .\c.xml`nGet-Credential -Credential `$cred"

            Returns Import-Clixml.

        .INPUTS
            None.

        .OUTPUTS
            System.String. The description of how the script builds the credential.
        #>
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [string]$Text
        )

        $ast = ConvertTo-Ast $Text
        $call = $ast.Find({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq 'Get-Credential'
            }, $true)
        $variable = $call.CommandElements[-1]
        InModuleScope IntuneScriptLab -Parameters @{ Variable = $variable; Ast = $ast } {
            @(Get-IslVariableCredentialSource -Variable $Variable -Ast $Ast)
        }
    }
}

Describe 'Get-IslVariableCredentialSource' -Tag 'Unit', 'Private' {

    It 'names every way the script builds the credential' {
        $text = "if (`$a) { `$cred = Import-Clixml .\c.xml } else { `$cred = [pscredential]::new(`$u, `$p) }`n" +
        'Get-Credential -Credential $cred'

        Get-Source -Text $text | Should-BeCollection @('Import-Clixml, [pscredential]::new()')
    }

    It 'takes a typed parameter and a scope prefix' {
        $text = "param([pscredential]`$Cred)`n`$script:Cred = Import-Clixml .\c.xml`n" +
        'Get-Credential -Credential $Cred'

        Get-Source -Text $text | Should-BeCollection @('Import-Clixml, a [pscredential] parameter')
    }

    It 'takes a typed assignment, whatever its right side is' {
        $text = "[pscredential]`$cred = Get-Secret -Name x`nGet-Credential -Credential `$cred"

        Get-Source -Text $text | Should-BeCollection @('a [pscredential] variable')
    }

    It 'gives nothing for a parameter that is not typed as a credential' {
        $text = "param(`$Cred)`nGet-Credential -Credential `$Cred"

        Get-Source -Text $text | Should-BeCollection @()
    }

    It 'gives nothing when one assignment could be something else' {
        $text = "`$cred = Import-Clixml .\c.xml`n`$cred = Get-Secret -Name x`nGet-Credential -Credential `$cred"

        Get-Source -Text $text | Should-BeCollection @()
    }

    It 'gives nothing for a variable the script never gives a value' {
        Get-Source -Text 'Get-Credential -Credential $cred' | Should-BeCollection @()
    }
}
