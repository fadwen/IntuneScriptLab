#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    One script of a tenant policy against its local candidates: NotInTenant, Missing, Ambiguous,
    InSync or Drifted.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    $script:Root = Join-Path $TestDrive 'scripts'
    $null = New-Item -ItemType Directory -Path $script:Root -Force
    $script:Text = "if (Test-Path C:\x) { exit 1 }`r`nexit 0"

    function script:Write-Local {
        <#
        .SYNOPSIS
            Writes a local candidate script below the test root and describes it.

        .DESCRIPTION
            Writes the text as UTF-8 without a byte order mark to a file of the given name in the
            folder $script:Root names, and returns an object with the FullName of that file, to
            pass to Compare-Script as a candidate.

        .PARAMETER Name
            The file name of the script below the test root.

        .PARAMETER Text
            The text of the script.

        .EXAMPLE
            Write-Local -Name 'same.ps1' -Text $script:Text

            Writes same.ps1 below the test root and returns an object whose FullName is its path.

        .INPUTS
            None.

        .OUTPUTS
            IntuneScriptLab.Test.LocalScript. An object with the FullName of the file.
        #>
        [CmdletBinding()]
        [OutputType('IntuneScriptLab.Test.LocalScript')]
        param(
            [string]$Name,

            [string]$Text
        )

        $file = Join-Path $script:Root $Name
        [System.IO.File]::WriteAllText($file, $Text, [System.Text.UTF8Encoding]::new($false))
        [pscustomobject]@{ PSTypeName = 'IntuneScriptLab.Test.LocalScript'; FullName = $file }
    }

    function script:Compare-Script {
        <#
        .SYNOPSIS
            Runs Compare-IslPolicyScript for the detection script of a remediation.

        .DESCRIPTION
            Calls the private function inside the module for the detection script of a remediation
            that runs as SYSTEM in 64-bit without a signature check, with the test root as the local
            folder. Extra replaces or adds parameters, so that each test names only what it is about.

        .PARAMETER Content
            The content of the tenant's script, as the Base64 text the policy holds.

        .PARAMETER Candidates
            The local scripts that may be the tenant's script, as Write-Local returns them.

        .PARAMETER Extra
            Parameters of Compare-IslPolicyScript that replace or add to the defaults.

        .EXAMPLE
            Compare-Script -Content $script:Tenant -Candidates @($local)

            Compares the tenant's script with one local copy and returns the drift results.

        .INPUTS
            None.

        .OUTPUTS
            IntuneScriptLab.DriftResult. What Compare-IslPolicyScript returns.
        #>
        [CmdletBinding()]
        [OutputType('IntuneScriptLab.DriftResult')]
        param(
            [string]$Content,

            [object[]]$Candidates,

            [hashtable]$Extra = @{}
        )

        $parameters = @{
            PolicyKind = 'Remediation'; Policy = @{ id = 'p1'; displayName = 'Fix-Widget' }; Role = 'detection'
            Content = $Content; Candidates = $Candidates; RunAsAccount = 'system'; RunAs32Bit = $false
            EnforceSignatureCheck = $false; Root = $script:Root; SettingsCache = @{}
        }
        foreach ($key in $Extra.Keys) { $parameters[$key] = $Extra[$key] }
        InModuleScope IntuneScriptLab -Parameters @{ Parameters = $parameters } {
            @(Compare-IslPolicyScript @Parameters)
        }
    }

    $script:Tenant = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($script:Text))
}

Describe 'Compare-IslPolicyScript' -Tag 'Unit', 'Private' {

    Context 'Core Functionality' {
        It 'reports InSync for a local copy that is the same byte for byte' {
            $local = Write-Local -Name 'same.ps1' -Text $script:Text
            $results = Compare-Script -Content $script:Tenant -Candidates @($local)

            $results | Should-BeCollection -Count 1
            $results[0] | Should-HaveType 'IntuneScriptLab.DriftResult'
            $results[0].State | Should-Be 'InSync'
            $results[0].LocalHash | Should-Be $results[0].TenantHash
            $results[0].LocalHash.Length | Should-Be 12
        }

        It 'reports Drifted with what differs' {
            $local = Write-Local -Name 'other.ps1' -Text "if (Test-Path C:\y) { exit 1 }`r`nexit 0"
            $results = Compare-Script -Content $script:Tenant -Candidates @($local)

            $results | Should-BeCollection -Count 1
            $results[0].State | Should-Be 'Drifted'
            $results[0].Differences | Should-BeCollection @('Content')
            $results[0].Detail | Should-BeLikeString 'content differs from line 1*'
        }

        It 'reports a run setting the local copy states that the policy does not have' {
            $local = Write-Local -Name 'user.ps1' -Text "# IntuneScriptLab: Context=User`r`n$($script:Text)"
            $results = Compare-Script -Content $script:Tenant -Candidates @($local)

            $results | Should-BeCollection -Count 1
            $results[0].State | Should-Be 'Drifted'
            $results[0].Differences | Should-ContainCollection @('Settings')
            $results[0].Detail | Should-BeLikeString '*Context=User locally, the policy runs as System'
        }

        It 'leaves the run context out under -SkipContext' {
            $local = Write-Local -Name 'skip.ps1' -Text "# IntuneScriptLab: Context=User`r`n$($script:Text)"
            $results = Compare-Script -Content $script:Tenant -Candidates @($local) -Extra @{ SkipContext = $true }

            $results | Should-BeCollection -Count 1
            @($results[0].Differences) | Should-BeCollection @('Content')
        }
    }

    Context 'Candidates' {
        It 'reports <State> for <Case>' -ForEach @(
            @{
                Case = 'no candidate'; Candidates = @(); State = 'Missing'
                Detail = "no local file for the detection script of 'Fix-Widget' under *"
            }
            @{
                Case = 'two candidates'; State = 'Ambiguous'; Detail = '2 local candidates: *'
                Candidates = @([pscustomobject]@{ FullName = 'a.ps1' }, [pscustomobject]@{ FullName = 'b.ps1' })
            }
            @{
                Case = 'a named file that is not there'; State = 'Missing'; Detail = '* does not exist'
                Candidates = @([pscustomobject]@{ FullName = 'C:\nowhere\none.ps1' })
            }
        ) {
            $results = Compare-Script -Content $script:Tenant -Candidates $Candidates

            $results | Should-BeCollection -Count 1
            $results[0].State | Should-Be $State
            $results[0].Detail | Should-BeLikeString $Detail
        }

        It 'reports NotInTenant for a local file of a script the policy does not have' {
            $local = Write-Local -Name 'extra.ps1' -Text $script:Text
            $results = Compare-Script -Content '' -Candidates @($local)

            $results | Should-BeCollection -Count 1
            $results[0].State | Should-Be 'NotInTenant'
            $results[0].Detail | Should-BeLikeString 'the policy has no detection script; * exists locally'
        }

        It 'reports nothing for a script neither side has' {
            Compare-Script -Content '' -Candidates @() | Should-BeCollection @()
        }
    }

    Context 'Error Handling' {
        It 'ends with the error of a tenant script that is not base64' {
            $local = Write-Local -Name 'b64.ps1' -Text $script:Text

            { Compare-Script -Content 'not base64!' -Candidates @($local) } |
                Should-Throw -ExceptionMessage '*Base-64*'
        }
    }
}
