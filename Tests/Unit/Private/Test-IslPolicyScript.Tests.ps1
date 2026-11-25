#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    One script of a tenant policy, written byte for byte and analyzed with the policy's settings.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    # A script's text as Graph stores it, base64, with a UTF-8 byte order mark
    function script:ConvertTo-Content {
        <#
        .SYNOPSIS
            Converts script text to Base64 content as Graph returns a deployed script.

        .DESCRIPTION
            Encodes the text as UTF-8 with a byte order mark and returns the bytes as Base64, the
            form of the script content in a Graph reply.

        .PARAMETER Text
            The text of the script.

        .EXAMPLE
            ConvertTo-Content -Text 'exit 0'

            Returns the Base64 content of a script that ends with exit code 0.

        .INPUTS
            None.

        .OUTPUTS
            System.String. The Base64 text.
        #>
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [string]$Text
        )

        $preamble = [System.Text.Encoding]::UTF8.GetPreamble()
        [System.Convert]::ToBase64String($preamble + [System.Text.Encoding]::UTF8.GetBytes($Text))
    }

    function script:Test-Script {
        <#
        .SYNOPSIS
            Tests a deployed detection script with Test-IslPolicyScript.

        .DESCRIPTION
            Calls Test-IslPolicyScript inside the module for a remediation detection that runs as
            system and calls Read-Host, with a new work folder under TestDrive. The given entries
            replace or add to those parameters, so that each test states only what it varies.

        .PARAMETER Extra
            Parameters of Test-IslPolicyScript that replace or add to the defaults, such as
            Content, RunAsAccount or ExcludeRule.

        .EXAMPLE
            Test-Script -Extra @{ ExcludeRule = 'IslInteractiveCall' }

            Returns the findings for the default script without its interactive call finding.

        .INPUTS
            None.

        .OUTPUTS
            IntuneScriptLab.DeploymentFinding. One object for each finding.
        #>
        [CmdletBinding()]
        [OutputType('IntuneScriptLab.DeploymentFinding')]
        param(
            [hashtable]$Extra = @{}
        )

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

        It 'refuses an id that cannot name a folder, and writes nothing' {
            $work = Join-Path $TestDrive 'bad-id'
            $policy = @{ id = '..\..\outside'; displayName = 'Detect Printer' }

            { Test-Script -Extra @{ WorkFolder = $work; Policy = $policy } } |
                Should-Throw -FullyQualifiedErrorId 'PolicyIdInvalid,*'
            Test-Path -LiteralPath $work | Should-BeFalse
        }

        It 'keeps a display name with path characters inside the policy''s folder' {
            $work = Join-Path $TestDrive 'dotted-name'
            $policy = @{ id = 'p1'; displayName = '..\..\Detect' }
            $content = ConvertTo-Content -Text 'exit 0'
            $null = Test-Script -Extra @{ WorkFolder = $work; Policy = $policy; Content = $content }

            Test-Path -LiteralPath (Join-Path $work 'Remediation\.._.._Detect-p1\detection.ps1') | Should-BeTrue
        }

        It 'refuses a path that would leave the work folder, and writes nothing' {
            $work = Join-Path $TestDrive 'escape'

            { Test-Script -Extra @{ WorkFolder = $work; Role = '..\..\..\escaped' } } |
                Should-Throw -FullyQualifiedErrorId 'PolicyPathOutsideWorkFolder,*'
            Test-Path -LiteralPath (Join-Path $TestDrive 'escaped.ps1') | Should-BeFalse
            Test-Path -LiteralPath $work | Should-BeFalse
        }
    }
}
