#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The result of a dependency or a superseded app in a Win32 app flow.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    function script:ConvertTo-Related {
        param([hashtable]$Parameters)
        InModuleScope IntuneScriptLab -Parameters @{ Parameters = $Parameters } {
            ConvertTo-IslWin32RelatedResult @Parameters
        }
    }
    $script:Pre = [pscustomobject]@{ Script = 'pre-script'; Rules = @('pre-rule') }
    $script:Post = [pscustomobject]@{ Script = 'post-script'; Rules = @('post-rule') }
}

Describe 'ConvertTo-IslWin32RelatedResult' -Tag 'Unit', 'Private' {

    It 'carries the name, the status, the runs and what each detection pass found' {
        $result = ConvertTo-Related @{
            Name = 'Runtime'; Relationship = 'dependency (autoInstall)'; Status = 'Installed after install'
            Pre = $script:Pre; Install = 'install-run'; Post = $script:Post
        }

        $result | Should-HaveType 'IntuneScriptLab.Win32RelatedResult'
        $result.Name | Should-Be 'Runtime'
        $result.Relationship | Should-Be 'dependency (autoInstall)'
        $result.Status | Should-Be 'Installed after install'
        $result.PreDetection | Should-Be 'pre-script'
        $result.PreRules | Should-BeCollection @('pre-rule')
        $result.Install | Should-Be 'install-run'
        $result.Uninstall | Should-BeNull
        $result.PostDetection | Should-Be 'post-script'
        $result.PostRules | Should-BeCollection @('post-rule')
    }

    It 'leaves the post-detection empty when there was none' {
        $result = ConvertTo-Related @{
            Name = 'Old'; Relationship = 'supersedence (update)'; Status = 'Installed (left in place by update)'
            Pre = $script:Pre
        }

        $result.PostDetection | Should-BeNull
        @($result.PostRules) | Should-BeCollection @()
    }
}
