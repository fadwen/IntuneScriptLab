#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    One script of a tenant policy, written byte for byte and analyzed with the policy's settings.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }

    # A script's text as Graph stores it, base64, with a UTF-8 byte order mark
    function script:ConvertTo-Content {
        param([string]$Text)
        $preamble = [System.Text.Encoding]::UTF8.GetPreamble()
        [System.Convert]::ToBase64String($preamble + [System.Text.Encoding]::UTF8.GetBytes($Text))
    }

    function script:Test-Script {
        param([hashtable]$Extra = @{})
        $parameters = @{
            PolicyKind = 'Remediation'; Policy = @{ id = 'p1'; displayName = 'Detect Printer' }
            Role = 'detection'; ScriptType = 'Detection'; RunAsAccount = 'system'
            Content = (ConvertTo-Content -Text "`$answer = Read-Host 'Continue?'`nexit 0")
            WorkFolder = Join-Path $TestDrive "work-$([guid]::NewGuid().ToString('N'))"
        }
        foreach ($key in $Extra.Keys) { $parameters[$key] = $Extra[$key] }
        InModuleScope IntuneScriptLab -Parameters @{ Parameters = $parameters } {
            @(Test-IslPolicyScript @Parameters)
        }
    }
}

Describe 'Test-IslPolicyScript' -Tag 'Unit', 'Private' {

    Context 'Core Functionality' {
        It 'analyzes the script and names the policy and role on each finding' {
            $findings = @(Test-Script | Where-Object { $_.RuleName -eq 'IslInteractiveCall' })

            $findings | Should-BeCollection -Count 1
            $findings[0] | Should-HaveType 'IntuneScriptLab.DeploymentFinding'
            $findings[0].PolicyName | Should-Be 'Detect Printer'
            $findings[0].Role | Should-Be 'detection'
            $findings[0].Severity | Should-Be 'Error'
        }

        It 'writes the script byte for byte under the policy''s own folder' {
            $work = Join-Path $TestDrive 'bytes'
            $content = ConvertTo-Content -Text 'exit 0'
            $null = Test-Script -Extra @{ WorkFolder = $work; Content = $content }

            $file = Join-Path $work 'Remediation\Detect_Printer-p1\detection.ps1'
            $bytes = [System.IO.File]::ReadAllBytes($file)
            [System.Convert]::ToBase64String($bytes) | Should-Be $content
        }

        It 'gives nothing for a policy without that script' {
            Test-Script -Extra @{ Content = '' } | Should-BeCollection @()
        }

        It 'leaves out what the caller''s rule selection leaves out' {
            $findings = Test-Script -Extra @{ ExcludeRule = 'IslInteractiveCall' }

            @($findings | Where-Object { $_.RuleName -eq 'IslInteractiveCall' }) | Should-BeCollection @()
        }
    }

    Context 'The run settings' {
        BeforeAll {
            Mock Test-IntuneScript -ModuleName IntuneScriptLab {
                $script:Analyzed = @{
                    Context = $Context; Architecture = $Architecture; Signature = [bool]$EnforceSignatureCheck
                }
                $script:AnalyzedSettings = $null -ne $Settings
            }
        }

        It 'runs <RunAsAccount> with runAs32Bit <RunAs32Bit> as <Context> on <Architecture>' -ForEach @(
            @{ RunAsAccount = 'user'; RunAs32Bit = $true; Context = 'User'; Architecture = 'x86' }
            @{ RunAsAccount = 'system'; RunAs32Bit = $false; Context = 'System'; Architecture = 'x64' }
            @{ RunAsAccount = $null; RunAs32Bit = $null; Context = 'System'; Architecture = 'x64' }
        ) {
            $null = Test-Script -Extra @{ RunAsAccount = $RunAsAccount; RunAs32Bit = $RunAs32Bit }

            $script:Analyzed['Context'] | Should-Be $Context
            $script:Analyzed['Architecture'] | Should-Be $Architecture
        }

        It 'passes the policy''s signature check, and the settings only when the caller gave them' {
            $null = Test-Script -Extra @{ EnforceSignatureCheck = $true }
            $script:Analyzed['Signature'] | Should-BeTrue
            $script:AnalyzedSettings | Should-BeFalse

            $null = Test-Script -Extra @{ Settings = @{ ExcludeRule = 'IslLongSleep' } }
            $script:AnalyzedSettings | Should-BeTrue
        }
    }

    Context 'Error Handling' {
        It 'ends with the error of a script that cannot be analyzed' {
            Mock Test-IntuneScript -ModuleName IntuneScriptLab { throw 'The script could not be read' }

            { Test-Script } | Should-Throw -ExceptionMessage 'The script could not be read'
        }
    }
}
