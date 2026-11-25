#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The run settings a local script states, against those of its tenant policy.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }

    function script:Compare-Directive {
        param([string]$Directive, [hashtable]$Policy)
        $folder = Join-Path $TestDrive "s-$([guid]::NewGuid().ToString('N'))"
        $null = New-Item -ItemType Directory -Path $folder
        $file = Join-Path $folder 'detect.ps1'
        [System.IO.File]::WriteAllText($file, "# IntuneScriptLab: $Directive`nexit 0")
        InModuleScope IntuneScriptLab -Parameters @{ File = $file; Policy = $Policy } {
            @(Compare-IslScriptSetting -File $File -Cache @{} @Policy)
        }
    }
}

Describe 'Compare-IslScriptSetting' -Tag 'Unit', 'Private' {

    It 'notes <Directive> against <Case>' -ForEach @(
        @{
            Directive = 'Context=User'; Case = 'a system policy'; Policy = @{ RunAsAccount = 'system' }
            Note = 'Context=User locally, the policy runs as System'
        }
        @{
            Directive = 'Architecture=x86'; Case = 'a 64-bit policy'; Policy = @{ RunAs32Bit = $false }
            Note = 'Architecture=x86 locally, the policy runs x64'
        }
        @{
            Directive = 'EnforceSignatureCheck=yes'; Case = 'no signature check'
            Policy = @{ EnforceSignatureCheck = $false }
            Note = 'EnforceSignatureCheck=True locally, False on the policy'
        }
    ) {
        $notes = @(Compare-Directive -Directive $Directive -Policy $Policy)

        $notes | Should-BeCollection -Count 1
        $notes[0] | Should-Be $Note
    }

    It 'notes nothing for <Case>' -ForEach @(
        @{
            Case = 'settings that match'; Directive = 'Context=User Architecture=x86'
            Policy = @{ RunAsAccount = 'user'; RunAs32Bit = $true }
        }
        @{
            Case = 'a context under -SkipContext'; Directive = 'Context=User'
            Policy = @{ RunAsAccount = 'system'; SkipContext = $true }
        }
    ) {
        Compare-Directive -Directive $Directive -Policy $Policy | Should-BeCollection @()
    }
}
