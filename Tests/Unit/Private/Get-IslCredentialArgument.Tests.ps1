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

    # The syntax tree of a script given as text
    function script:ConvertTo-Ast {
        param([string]$Text)
        [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null)
    }

    function script:Get-Argument {
        param([string]$Text)
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
