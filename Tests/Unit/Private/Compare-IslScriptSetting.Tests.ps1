#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The run settings a local script states, against those of its tenant policy.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    function script:Compare-Directive {
        <#
        .SYNOPSIS
            Writes a script with a directive and compares it with a policy's settings.

        .DESCRIPTION
            Writes detect.ps1 into a new folder under TestDrive with the directive in its first line,
            then runs the module's private Compare-IslScriptSetting on it with the policy's settings
            and an empty cache, and returns the notes as an array.

        .PARAMETER Directive
            The text after 'IntuneScriptLab:' in the directive, such as 'Context=User'.

        .PARAMETER Policy
            The settings of the tenant policy, splatted onto Compare-IslScriptSetting, such as
            @{ RunAsAccount = 'system' }.

        .EXAMPLE
            Compare-Directive -Directive 'Context=User' -Policy @{ RunAsAccount = 'system' }

            Returns the note that the script runs as User locally and as System under the policy.

        .INPUTS
            None.

        .OUTPUTS
            System.String. One note for each setting that differs.
        #>
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [string]$Directive,

            [hashtable]$Policy
        )

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
