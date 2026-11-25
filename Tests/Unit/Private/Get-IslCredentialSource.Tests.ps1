#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    How an expression builds a credential, for the interactive-call rule.
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

    function script:Get-Source {
        param([string]$Text)
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
    ) {
        Get-Source -Text $Text | Should-BeCollection @()
    }

    It 'gives nothing for no expression' {
        InModuleScope IntuneScriptLab { @(Get-IslCredentialSource -Expression $null) } | Should-BeCollection @()
    }
}
