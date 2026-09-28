#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    How a script's type, context and architecture are resolved: explicit parameters win, then
    the directive comment, then the file name, then Intune's portal defaults. The defaults are
    the observed ones (Validation\Findings.md): platform scripts run as the user in 32-bit,
    remediations as SYSTEM in 32-bit, Win32 detection in 64-bit.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')

    function Get-ScriptContext {
        param([string]$Path, [hashtable]$Options = @{})
        InModuleScope IntuneScriptLab -Parameters @{ Path = $Path; Options = $Options } {
            Get-IslScriptContext -Path $Path @Options
        }
    }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Get-IslScriptContext' -Tag 'Unit', 'Private' {

    Context 'Parameter Validation' {
        It 'fails on a path that does not exist' {
            { Get-ScriptContext -Path (Join-Path $TestDrive 'missing.ps1') } | Should-Throw
        }

        It 'rejects values outside the sets' {
            $path = New-TestScript 'a.ps1' 'exit 0'
            { Get-ScriptContext -Path $path -Options @{ ScriptType = 'Other' } } | Should-Throw
            { Get-ScriptContext -Path $path -Options @{ Architecture = 'ia64' } } | Should-Throw
        }
    }

    Context 'Signature check' {
        It 'is off by default' {
            $path = New-TestScript 'Detect-App.ps1' 'exit 0'
            (Get-ScriptContext -Path $path).EnforceSignatureCheck | Should-BeFalse
        }

        It 'reads EnforceSignatureCheck=<Word> from the directive as <Expected>' -ForEach @(
            @{ Word = 'true';  Expected = $true }
            @{ Word = 'True';  Expected = $true }
            @{ Word = 'false'; Expected = $false }
        ) {
            $body = "# IntuneScriptLab: ScriptType=Win32Detection EnforceSignatureCheck=$Word`nexit 0"
            $path = New-TestScript "Detect-$Word.ps1" $body
            $scriptContext = Get-ScriptContext -Path $path
            $scriptContext.EnforceSignatureCheck | Should-Be $Expected
            $scriptContext.ScriptType | Should-Be 'Win32Detection'
        }

        It 'lets the parameter override the directive' {
            $path = New-TestScript 'Detect-Over.ps1' "# IntuneScriptLab: EnforceSignatureCheck=true`nexit 0"
            (Get-ScriptContext -Path $path -Options @{ EnforceSignatureCheck = 'False' }).EnforceSignatureCheck |
                Should-BeFalse
            (Get-ScriptContext -Path $path -Options @{ EnforceSignatureCheck = 'True' }).EnforceSignatureCheck |
                Should-BeTrue
        }
    }

    Context 'Type inference from the file name' {
        It 'infers <Expected> from <Name>' -ForEach @(
            @{ Name = 'Detect-App.ps1';          Expected = 'Win32Detection' }
            @{ Name = 'detect-win32-agent.ps1';  Expected = 'Win32Detection' }
            @{ Name = 'Detect-LegacyTls.ps1';    Expected = 'Detection' }
            @{ Name = 'Remediate-LegacyTls.ps1'; Expected = 'Remediation' }
            @{ Name = 'Fix-Proxy.ps1';           Expected = 'Remediation' }
            @{ Name = 'prefix-check.ps1';        Expected = 'PlatformScript' }
            @{ Name = 'undetectable.ps1';        Expected = 'PlatformScript' }
            @{ Name = 'App-Requirement.ps1';     Expected = 'Win32Requirement' }
            @{ Name = 'Configure-Proxy.ps1';     Expected = 'PlatformScript' }
        ) {
            $scriptContext = Get-ScriptContext -Path (New-TestScript $Name 'exit 0')
            $scriptContext.ScriptType | Should-Be $Expected
            $scriptContext.TypeSource | Should-Be 'inferred from file name'
        }

        It 'lets a nearby folder settle a detection: <Path> is <Expected>' -ForEach @(
            @{ Path = 'Win32\Agent\Detect.ps1';            Expected = 'Win32Detection' }
            @{ Path = 'Apps\Agent\Detect-Agent.ps1';       Expected = 'Win32Detection' }
            @{ Path = 'Remediations\Tls\Detect-App.ps1';   Expected = 'Detection' }
            @{ Path = 'HealthScripts\Detect-Install.ps1';  Expected = 'Detection' }
        ) {
            $scriptContext = Get-ScriptContext -Path (New-TestScript $Path 'exit 0')
            $scriptContext.ScriptType | Should-Be $Expected
            $scriptContext.TypeSource | Should-Be 'inferred from folder and file name'
        }

        It 'looks no further than two folders up, and only at detections' {
            (Get-ScriptContext -Path (New-TestScript 'Win32\a\b\Detect.ps1' 'exit 0')).ScriptType |
                Should-Be 'Detection'
            (Get-ScriptContext -Path (New-TestScript 'Win32\Agent\Configure.ps1' 'exit 0')).ScriptType |
                Should-Be 'PlatformScript'
        }
    }

    Context 'Precedence' {
        It 'lets the directive override the file name and records the source' {
            $directive = "# IntuneScriptLab: ScriptType=Win32Detection Context=User`nexit 0"
            $scriptContext = Get-ScriptContext -Path (New-TestScript 'Detect-X.ps1' $directive)
            $scriptContext.ScriptType | Should-Be 'Win32Detection'
            $scriptContext.TypeSource | Should-Be 'directive'
            $scriptContext.Context | Should-Be 'User'
        }

        It 'reads the directive anywhere in the script, with commas or spaces' {
            $path = New-TestScript 'x.ps1' "exit 0`n#IntuneScriptLab:Architecture=arm64,ScriptType=Remediation"
            $scriptContext = Get-ScriptContext -Path $path
            $scriptContext.ScriptType | Should-Be 'Remediation'
            $scriptContext.Architecture | Should-Be 'arm64'
        }

        It 'takes the type, context, architecture and signature check from settings below the directive' {
            $path = New-TestScript 'plain.ps1' 'exit 0'
            $fromSettings = InModuleScope IntuneScriptLab -Parameters @{ Path = $path } {
                $settings = Get-IslSetting -Path $Path -Settings @{
                    ScriptType = 'Win32Requirement'; Context = 'User'; Architecture = 'arm64'
                    EnforceSignatureCheck = $true
                }
                Get-IslScriptContext -Path $Path -Settings $settings
            }
            $fromSettings.ScriptType | Should-Be 'Win32Requirement'
            $fromSettings.TypeSource | Should-Be 'settings'
            $fromSettings.Context | Should-Be 'User'
            $fromSettings.Architecture | Should-Be 'arm64'
            $fromSettings.EnforceSignatureCheck | Should-BeTrue
            $directiveBody = "# IntuneScriptLab: ScriptType=Detection Context=System`nexit 0"
            $directive = New-TestScript 'directive.ps1' $directiveBody
            $overridden = InModuleScope IntuneScriptLab -Parameters @{ Path = $directive } {
                $table = @{ ScriptType = 'Win32Requirement'; Context = 'User' }
                $settings = Get-IslSetting -Path $Path -Settings $table
                Get-IslScriptContext -Path $Path -Settings $settings
            }
            $overridden.ScriptType | Should-Be 'Detection'
            $overridden.TypeSource | Should-Be 'directive'
            $overridden.Context | Should-Be 'System'
        }

        It 'lets explicit parameters win over the directive' {
            $directive = "# IntuneScriptLab: ScriptType=Win32Detection Context=User`nexit 0"
            $path = New-TestScript 'Detect-X.ps1' $directive
            $options = @{ ScriptType = 'PlatformScript'; Context = 'System'; Architecture = 'x64' }
            $scriptContext = Get-ScriptContext -Path $path -Options $options
            $scriptContext.ScriptType | Should-Be 'PlatformScript'
            $scriptContext.TypeSource | Should-Be 'parameter'
            $scriptContext.Context | Should-Be 'System'
            $scriptContext.Architecture | Should-Be 'x64'
        }
    }

    Context 'Portal defaults' {
        It 'gives <Type> the context <Context> and the <Architecture> host' -ForEach @(
            @{ Type = 'PlatformScript';   Context = 'User';   Architecture = 'x86' }
            @{ Type = 'Detection';        Context = 'System'; Architecture = 'x86' }
            @{ Type = 'Remediation';      Context = 'System'; Architecture = 'x86' }
            @{ Type = 'Win32Detection';   Context = 'System'; Architecture = 'x64' }
            @{ Type = 'Win32Requirement'; Context = 'System'; Architecture = 'x64' }
        ) {
            $path = New-TestScript 'x.ps1' 'exit 0'
            $scriptContext = Get-ScriptContext -Path $path -Options @{ ScriptType = $Type }
            $scriptContext.Context | Should-Be $Context
            $scriptContext.Architecture | Should-Be $Architecture
        }
    }

    Context 'Core Functionality' {
        It 'carries the AST, tokens, bytes and parse errors' {
            $path = New-TestScript 'x.ps1' 'if ($true) { exit 0' -Bom
            $scriptContext = Get-ScriptContext -Path $path
            $scriptContext.PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.ScriptContext'
            $scriptContext.Ast | Should-NotBeNull
            @($scriptContext.Tokens).Count | Should-BeGreaterThan 0
            $scriptContext.Bytes[0] | Should-Be 0xEF
            @($scriptContext.ParseErrors).Count | Should-BeGreaterThan 0
            $scriptContext.Path | Should-Be $path
        }
    }
}
