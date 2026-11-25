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

    # The syntax tree of a script given as text
    function script:ConvertTo-Ast {
        param([string]$Text)
        [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null)
    }

    # The source of the variable that Get-Credential is handed in the script
    function script:Get-Source {
        param([string]$Text)
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
