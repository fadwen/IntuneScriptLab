#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The release script's reading of the Gallery API key from a secret vault, tested without a vault.
    Publish-Module.ps1 requires PowerShell 7.6 and stages a package when it runs, so its function is
    lifted out through the AST into a file under TestDrive and dot-sourced from there. Get-Secret and
    Get-SecretVault are stubbed, because Microsoft.PowerShell.SecretManagement is not installed on a
    CI runner, and then mocked.
#>

BeforeAll {
    $repositoryRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    $buildFolder = Join-Path -Path $repositoryRoot -ChildPath 'Build'
    $script:releaseScript = Join-Path -Path $buildFolder -ChildPath 'Publish-Module.ps1'

    $tokens = $null
    $parseErrors = $null
    $script:releaseAst = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:releaseScript, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors) {
        throw "Publish-Module.ps1 does not parse: $($parseErrors[0].Message)"
    }
    $definition = $script:releaseAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'Get-VaultApiKey'
        }, $false)
    if ($null -eq $definition) {
        throw 'Publish-Module.ps1 no longer defines Get-VaultApiKey.'
    }
    $lifted = Join-Path -Path $TestDrive -ChildPath 'Get-VaultApiKey.ps1'
    [System.IO.File]::WriteAllText($lifted, $definition.Extent.Text)

    function Get-SecretVault {
        <#
        .SYNOPSIS
        Stands in for Get-SecretVault of Microsoft.PowerShell.SecretManagement.

        .DESCRIPTION
        Exists so that the command can be mocked where the module is not installed. It returns
        nothing; each test supplies the vaults through a mock.

        .EXAMPLE
        Mock -CommandName Get-SecretVault -MockWith { [PSCustomObject]@{ Name = 'Main'; IsDefault = $true } }

        Replaces the stand-in with one default vault.

        .INPUTS
        None.

        .OUTPUTS
        None.
        #>
        [CmdletBinding()]
        [OutputType([void])]
        param()
    }

    function Get-Secret {
        <#
        .SYNOPSIS
        Stands in for Get-Secret of Microsoft.PowerShell.SecretManagement.

        .DESCRIPTION
        Exists so that the command can be mocked where the module is not installed, with the
        parameters the release script passes. It returns nothing; each test supplies the secret
        through a mock.

        .PARAMETER Name
        Name of the secret.

        .PARAMETER Vault
        Name of the vault.

        .PARAMETER AsPlainText
        Asks for the secret as text. The release script must not pass it.

        .EXAMPLE
        Mock -CommandName Get-Secret -MockWith { $script:storedSecret }

        Replaces the stand-in with one that returns a SecureString.

        .INPUTS
        None.

        .OUTPUTS
        None.
        #>
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSReviewUnusedParameter', '', Justification = 'A stand-in that is mocked; it has no body.')]
        [CmdletBinding()]
        [OutputType([void])]
        param(
            [Parameter()]
            [string]$Name,

            [Parameter()]
            [string]$Vault,

            [Parameter()]
            [switch]$AsPlainText
        )
    }

    . $lifted

    # NetworkCredential converts between text and a SecureString in both directions. PSScriptAnalyzer
    # reports ConvertTo-SecureString -AsPlainText, and the text here is not a secret.
    $script:storedText = 'value-from-the-vault'
    $script:storedSecret = [System.Net.NetworkCredential]::new('', $script:storedText).SecurePassword
}

Describe 'Get-VaultApiKey' -Tag 'Unit', 'Build' {
    Context 'Parameter Validation' {
        It 'Declares SecretName as a mandatory string and VaultName as an optional one' {
            $command = Get-Command -Name Get-VaultApiKey

            $command | Should-HaveParameter -ParameterName 'SecretName' -Type ([string]) -Mandatory
            $command | Should-HaveParameter -ParameterName 'VaultName' -Type ([string])
            $command.Parameters['VaultName'].Attributes.Where({ $_ -is [Parameter] }).Mandatory |
                Should-BeFalse
        }
    }

    Context 'Core Functionality' {
        BeforeEach {
            Mock -CommandName Get-SecretVault -MockWith {
                [PSCustomObject]@{ Name = 'Other'; IsDefault = $false }
                [PSCustomObject]@{ Name = 'Main'; IsDefault = $true }
            }
            Mock -CommandName Get-Secret -MockWith { $script:storedSecret }
        }

        It 'Reads the named vault, and no other, when a vault is named' {
            $key = Get-VaultApiKey -SecretName 'Gallery' -VaultName 'Named'

            $key | Should-HaveType ([securestring])
            [System.Net.NetworkCredential]::new('', $key).Password | Should-Be $script:storedText
            Should-Invoke -CommandName Get-Secret -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'Gallery' -and $Vault -eq 'Named'
            }
            Should-Invoke -CommandName Get-SecretVault -Times 0 -Exactly
        }

        It 'Reads the default vault when no vault is named' {
            $key = Get-VaultApiKey -SecretName 'Gallery'

            [System.Net.NetworkCredential]::new('', $key).Password | Should-Be $script:storedText
            Should-Invoke -CommandName Get-Secret -Times 1 -Exactly -ParameterFilter { $Vault -eq 'Main' }
        }

        It 'Does not ask the vault for plain text' {
            $null = Get-VaultApiKey -SecretName 'Gallery' -VaultName 'Named'

            Should-Invoke -CommandName Get-Secret -Times 1 -Exactly -ParameterFilter { -not $AsPlainText }
        }

        It 'Returns the password of a secret that is stored as a credential' {
            Mock -CommandName Get-Secret -MockWith {
                [System.Management.Automation.PSCredential]::new('gallery', $script:storedSecret)
            }

            $key = Get-VaultApiKey -SecretName 'Gallery' -VaultName 'Named'

            $key | Should-HaveType ([securestring])
            [System.Net.NetworkCredential]::new('', $key).Password | Should-Be $script:storedText
        }
    }

    Context 'Error Handling' {
        It 'Warns and returns nothing when no default vault is registered' {
            Mock -CommandName Get-SecretVault -MockWith { [PSCustomObject]@{ Name = 'Other'; IsDefault = $false } }
            Mock -CommandName Get-Secret -MockWith { $script:storedSecret }

            $quiet = @{ WarningVariable = 'warnings'; WarningAction = 'SilentlyContinue' }
            $key = Get-VaultApiKey -SecretName 'Gallery' @quiet

            $key | Should-BeNull
            $warnings | Should-BeCollection -Count 1
            "$($warnings[0])" | Should-BeLikeString '*No default secret vault*-VaultName*'
            Should-Invoke -CommandName Get-Secret -Times 0 -Exactly
        }

        It 'Warns with the vault and the reason, and returns nothing, when the vault cannot be read' {
            Mock -CommandName Get-Secret -MockWith { throw 'A valid password is required to access the store.' }

            $quiet = @{ WarningVariable = 'warnings'; WarningAction = 'SilentlyContinue' }
            $key = Get-VaultApiKey -SecretName 'Gallery' -VaultName 'Named' @quiet

            $key | Should-BeNull
            $warnings | Should-BeCollection -Count 1
            "$($warnings[0])" | Should-BeLikeString "*'Gallery'*'Named'*A valid password is required*"
        }

        It 'Warns and returns nothing when the secret is not text' {
            Mock -CommandName Get-Secret -MockWith { @{ Key = 'value' } }

            $quiet = @{ WarningVariable = 'warnings'; WarningAction = 'SilentlyContinue' }
            $key = Get-VaultApiKey -SecretName 'Gallery' -VaultName 'Named' @quiet

            $key | Should-BeNull
            $warnings | Should-BeCollection -Count 1
            "$($warnings[0])" | Should-BeLikeString '*is not text*'
        }
    }
}

Describe 'Publish-Module.ps1 secret handling' -Tag 'Unit', 'Build' {
    BeforeAll {
        $script:secretCalls = @($script:releaseAst.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq 'Get-Secret'
                }, $true))
    }

    It 'Names the vault on every Get-Secret call and never asks for plain text' {
        $script:secretCalls | Should-BeCollection -Count 1
        $parameterNames = @($script:secretCalls[0].CommandElements |
                Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] } |
                ForEach-Object { $_.ParameterName })

        $parameterNames | Should-ContainCollection @('Vault')
        $parameterNames | Should-NotContainCollection @('AsPlainText')
    }

    It 'Requires a PowerShell version that is still supported' {
        $script:releaseAst.ScriptRequirements.RequiredPSVersion | Should-BeGreaterThanOrEqual ([version]'7.6')
    }
}
