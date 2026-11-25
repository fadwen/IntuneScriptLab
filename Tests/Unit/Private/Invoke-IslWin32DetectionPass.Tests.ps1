#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    One detection pass of a Win32 app, with the detection script and the rules mocked.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }

    function script:Invoke-Pass {
        param([hashtable]$Parameters)
        InModuleScope IntuneScriptLab -Parameters @{ Parameters = $Parameters } {
            Invoke-IslWin32DetectionPass @Parameters
        }
    }
    $script:MetRule = @{ Type = 'File'; Path = 'C:\x'; FileOrFolderName = 'present.txt' }
    $script:UnmetRule = @{ Type = 'File'; Path = 'C:\x'; FileOrFolderName = 'missing.txt' }
}

Describe 'Invoke-IslWin32DetectionPass' -Tag 'Unit', 'Private' {

    BeforeEach {
        $script:Warnings = [System.Collections.Generic.List[string]]::new()
        Mock Test-IntuneWin32Rule -ModuleName IntuneScriptLab {
            $met = $Rule.FileOrFolderName -ne 'missing.txt'
            [pscustomobject]@{ Met = $met; Kind = 'File'; Operation = 'Exists'; Reason = "reason $met" }
        }
        Mock Invoke-IntuneDetectionTest -ModuleName IntuneScriptLab {
            [pscustomobject]@{ Detected = $true; TimedOut = $false; Reason = 'Exit 0 with stdout and no stderr' }
        }
    }

    It 'says detected when the script and every rule say installed' {
        $pass = Invoke-Pass @{
            Phase = 'Pre'; Path = 'C:\lab\detect.ps1'; Rule = @($script:MetRule)
            Detection = @{ Architecture = 'x64' }; Warning = $script:Warnings
        }

        $pass | Should-HaveType 'IntuneScriptLab.Win32DetectionPass'
        $pass.Detected | Should-BeTrue
        $pass.Reason | Should-Be 'Script and rules all report installed'
        $script:Warnings | Should-BeCollection @()
        Should-Invoke Invoke-IntuneDetectionTest -ModuleName IntuneScriptLab -Times 1 -Exactly -ParameterFilter {
            $Path -eq 'C:\lab\detect.ps1' -and $Architecture -eq 'x64' -and $ErrorAction -eq 'Stop'
        }
    }

    It 'says not detected for one rule that is not met, and adds a warning for it' {
        $pass = Invoke-Pass @{
            Phase = 'Post'; Rule = @($script:MetRule, $script:UnmetRule); Label = ' for dependency Runtime'
            Detection = @{}; Warning = $script:Warnings
        }

        $pass.Detected | Should-BeFalse
        $pass.Reason | Should-Be 'reason False'
        $script:Warnings | Should-BeCollection -Count 1
        $expected = 'Post detection rule not met for dependency Runtime (File Exists): reason False'
        $script:Warnings[0] | Should-Be $expected
        Should-Invoke Invoke-IntuneDetectionTest -ModuleName IntuneScriptLab -Times 0 -Exactly
    }

    It 'gives the script''s reason when the script says not installed' {
        Mock Invoke-IntuneDetectionTest -ModuleName IntuneScriptLab {
            [pscustomobject]@{ Detected = $false; TimedOut = $true; Reason = 'Timed out after 3 s' }
        }

        $passSplat = @{ Phase = 'Pre'; Path = 'C:\lab\detect.ps1'; Detection = @{}; Warning = $script:Warnings }
        $pass = Invoke-Pass $passSplat

        $pass.Detected | Should-BeFalse
        $pass.TimedOut | Should-BeTrue
        $pass.Reason | Should-Be 'Timed out after 3 s'
    }

    It 'ends with DetectionRuleEmpty for a rule entry that is null, and runs nothing' {
        $pass = @{
            Phase = 'Pre'; Rule = @($script:MetRule, $null); Label = ' for dependency Runtime'
            Detection = @{}; Warning = $script:Warnings
        }

        { Invoke-Pass $pass } | Should-Throw -FullyQualifiedErrorId 'DetectionRuleEmpty,*' -ExceptionMessage (
            'Detection rule 2 for dependency Runtime is empty')
        Should-Invoke Test-IntuneWin32Rule -ModuleName IntuneScriptLab -Times 0 -Exactly
    }

    It 'ends with DetectionRuleEmpty for rules that are all null, as an entry of -DependsOn can give' {
        $pass = @{ Phase = 'Pre'; Rule = @($null, $null); Detection = @{}; Warning = $script:Warnings }

        { Invoke-Pass $pass } | Should-Throw -FullyQualifiedErrorId 'DetectionRuleEmpty,*'
    }

    It 'ends with DetectionMissing for a pass with neither a script nor a rule' {
        $pass = @{ Phase = 'Post'; Label = ' for superseded app Old'; Detection = @{}; Warning = $script:Warnings }

        { Invoke-Pass $pass } | Should-Throw -FullyQualifiedErrorId 'DetectionMissing,*' -ExceptionMessage (
            'The Post detection for superseded app Old has no script and no rules')
    }

    It 'ends with the error of a detection script that cannot be run' {
        Mock Invoke-IntuneDetectionTest -ModuleName IntuneScriptLab { throw 'The host could not be started.' }

        $passSplat = @{ Phase = 'Pre'; Path = 'C:\lab\detect.ps1'; Detection = @{}; Warning = $script:Warnings }
        { Invoke-Pass $passSplat } | Should-Throw -ExceptionMessage '*host could not be started*'
    }
}
