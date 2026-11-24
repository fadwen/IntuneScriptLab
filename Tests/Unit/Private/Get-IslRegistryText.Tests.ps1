#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    A registry key as lines of text for the diagnostic package. The keys are made in Pester's
    TestRegistry drive, which Pester removes after the file.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }

    function script:Get-Text {
        param([string]$Key, [int]$Depth)
        InModuleScope IntuneScriptLab -Parameters @{ Key = $Key; Depth = $Depth } {
            @(Get-IslRegistryText -Key $Key -Depth $Depth)
        }
    }

    $script:Key = 'TestRegistry:\Policies'
    $null = New-Item -Path $script:Key
    $null = New-ItemProperty -Path $script:Key -Name 'Name' -Value 'Widget'
    $null = New-ItemProperty -Path $script:Key -Name 'Blob' -PropertyType Binary -Value ([byte[]](1, 2, 3))
    $null = New-ItemProperty -Path $script:Key -Name 'Long' -Value ('x' * 450)
    $null = New-Item -Path "$($script:Key)\Child"
    $null = New-ItemProperty -Path "$($script:Key)\Child" -Name 'Inner' -Value 1
    $null = New-Item -Path "$($script:Key)\Child\Grandchild"
}

Describe 'Get-IslRegistryText' -Tag 'Unit', 'Private' {

    It 'writes each key and each of its values, and leaves out the provider''s own properties' {
        $lines = Get-Text -Key $script:Key -Depth 3

        $lines[0] | Should-BeLikeString '`[*\Policies`]'
        $lines | Should-ContainCollection '  Name = Widget'
        @($lines | Where-Object { $_ -like '  PS*' }) | Should-BeCollection @()
        @($lines | Where-Object { $_ -like '`[*\Child`]' }) | Should-BeCollection -Count 1
        $lines | Should-ContainCollection '  Inner = 1'
    }

    It 'shows a binary value by its length and cuts a long value at 400 characters' {
        $lines = Get-Text -Key $script:Key -Depth 0

        $lines | Should-ContainCollection '  Blob = byte[3]'
        $long = @($lines | Where-Object { $_ -like '  Long = *' })
        $long | Should-BeCollection -Count 1
        $long[0] | Should-Be ('  Long = ' + ('x' * 400) + '...')
    }

    It 'goes down as many levels as asked' {
        $shallow = Get-Text -Key $script:Key -Depth 0
        $deep = Get-Text -Key $script:Key -Depth 1

        @($shallow | Where-Object { $_ -like '`[*' }).Count | Should-Be 2
        @($deep | Where-Object { $_ -like '`[*Grandchild`]' }) | Should-BeCollection -Count 1
    }

    It 'gives one line for a key that is not there' {
        $missing = 'TestRegistry:\NotThere'
        Get-Text -Key $missing -Depth 1 | Should-BeCollection @("$missing : not present")
    }
}
