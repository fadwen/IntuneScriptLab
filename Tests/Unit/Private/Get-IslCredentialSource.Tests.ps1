#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    How an expression builds a credential, for the interactive-call rule.
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
        <#
        .SYNOPSIS
            Converts script text to its syntax tree.

        .DESCRIPTION
            Parses the text with the PowerShell parser and returns the tree. Parse errors are not
            reported, because the cases only need the nodes the text holds.

        .PARAMETER Text
            The text of the script.

        .EXAMPLE
            ConvertTo-Ast '$x = 1'

            Returns the syntax tree of the assignment.

        .INPUTS
            None.

        .OUTPUTS
            System.Management.Automation.Language.ScriptBlockAst. The tree of the whole text.
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
            Gets how an expression builds a credential, from Get-IslCredentialSource.

        .DESCRIPTION
            Parses the expression as the right side of an assignment and runs the module's private
            Get-IslCredentialSource on that side, inside the module, returning its result as an array.

        .PARAMETER Text
            The expression, such as '[pscredential]::new($user, $secure)'.

        .EXAMPLE
            Get-Source -Text 'New-Object PSCredential $user, $secure'

            Returns 'New-Object PSCredential'.

        .INPUTS
            None.

        .OUTPUTS
            System.String. How the expression builds the credential, or nothing.
        #>
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [string]$Text
        )

        $assignment = (ConvertTo-Ast "`$x = $Text").Find({
                param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst]
            }, $true)
        InModuleScope IntuneScriptLab -Parameters @{ Expression = $assignment.Right } {
            @(Get-IslCredentialSource -Expression $Expression)
        }
    }
}

Describe 'Get-IslCredentialSource' -Tag 'Unit', 'Private' {

    It 'reads <Text> as <Expected>' -ForEach @(
        @{ Text = '[pscredential]::new($user, $secure)'; Expected = '[pscredential]::new()' }
        @{ Text = '[pscredential]::"new"($user, $secure)'; Expected = '[pscredential]::new()' }
        @{
            Text = '[System.Management.Automation.PSCredential]::new($user, $secure)'
            Expected = '[pscredential]::new()'
        }
        @{ Text = 'New-Object PSCredential $user, $secure'; Expected = 'New-Object PSCredential' }
        @{
            Text = 'New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $a'
            Expected = 'New-Object PSCredential'
        }
        @{ Text = '[pscredential]$value'; Expected = 'a [pscredential] cast' }
        @{ Text = 'Import-Clixml -Path .\cred.xml'; Expected = 'Import-Clixml' }
        @{ Text = '(Import-Clixml -Path .\cred.xml)'; Expected = 'Import-Clixml' }
    ) {
        $source = @(Get-Source -Text $Text)

        $source | Should-BeCollection -Count 1
        $source[0] | Should-Be $Expected
    }

    It 'gives nothing for <Text>' -ForEach @(
        @{ Text = 'Get-Secret -Name Lab' }
        @{ Text = '$other.Credential' }
        @{ Text = 'New-Object System.Net.WebClient' }
        @{ Text = "'LAB\user'" }
        @{ Text = '[pscredential]::$m($user, $secure)' }
        @{ Text = '[pscredential]::"$m"($user, $secure)' }
    ) {
        Get-Source -Text $Text | Should-BeCollection @()
    }

    It 'gives nothing for no expression' {
        InModuleScope IntuneScriptLab { @(Get-IslCredentialSource -Expression $null) } | Should-BeCollection @()
    }
}
