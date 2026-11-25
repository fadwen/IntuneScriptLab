#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Whether a tenant policy is one that the caller's -Name and -Id select, as the three tenant
    commands select them.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    function script:Test-Policy {
        param([hashtable]$Selection)
        InModuleScope IntuneScriptLab -Parameters @{ Selection = $Selection } {
            # One policy as Invoke-MgGraphRequest returns it, a dictionary
            $policy = @{ id = 'policy-1'; displayName = 'Detect-Printer' }
            Test-IslPolicySelected -Policy $policy @Selection
        }
    }
}

Describe 'Test-IslPolicySelected' -Tag 'Unit', 'Private' {

    It 'gives <Expected> for <Case>' -ForEach @(
        @{ Case = 'the default name'; Selection = @{}; Expected = $true }
        @{ Case = 'a matching name'; Selection = @{ Name = 'Detect-*'; NameGiven = $true }; Expected = $true }
        @{ Case = 'another name'; Selection = @{ Name = 'Fix-*'; NameGiven = $true }; Expected = $false }
        @{ Case = 'its id alone'; Selection = @{ Id = 'policy-1' }; Expected = $true }
        @{ Case = 'another id alone, past the default name'; Selection = @{ Id = 'policy-2' }; Expected = $false }
        @{
            Case = 'another id with a matching name given'
            Selection = @{ Id = 'policy-2'; Name = 'Detect-*'; NameGiven = $true }; Expected = $true
        }
        @{
            Case = 'its id with another name given'
            Selection = @{ Id = 'policy-1'; Name = 'Fix-*'; NameGiven = $true }; Expected = $true
        }
    ) {
        Test-Policy -Selection $Selection | Should-Be $Expected
    }

    It 'reads a policy that is an object, as a recorded fixture is' {
        $selected = InModuleScope IntuneScriptLab {
            $policy = '{ "id": "policy-1", "displayName": "Detect-Printer" }' | ConvertFrom-Json
            Test-IslPolicySelected -Policy $policy -Name 'Detect-*' -NameGiven
        }

        $selected | Should-BeTrue
    }
}
