#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The settings file: found by walking up from the script, the nearest one winning, validated,
    cached per folder, or given directly as a path or a hashtable.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    $script:Tree = Join-Path $TestDrive 'repo'
    $null = New-Item -ItemType Directory -Path (Join-Path $script:Tree 'Intune\Remediations\Widget') -Force
    $null = New-Item -ItemType Directory -Path (Join-Path $script:Tree 'Intune\Win32\App') -Force
    $null = New-Item -ItemType Directory -Path (Join-Path $script:Tree 'Other') -Force
    @'
@{
    ExcludeRule = @('IslAssumedContext')
    MinimumSeverity = 'Warning'
    Severity = @{ IslLongSleep = 'Information' }
    Context = 'System'
}
'@ | Set-Content (Join-Path $script:Tree 'IntuneScriptLab.settings.psd1')
    @'
@{
    ScriptType = 'Win32Detection'
    EnforceSignatureCheck = $true
}
'@ | Set-Content (Join-Path $script:Tree 'Intune\Win32\IntuneScriptLab.settings.psd1')
    foreach ($script in 'Intune\Remediations\Widget\Detect.ps1', 'Intune\Win32\App\Detect.ps1', 'Other\Run.ps1') {
        Set-Content (Join-Path $script:Tree $script) 'exit 0'
    }

    function script:Get-Setting {
        param([string]$Relative, $Settings, [hashtable]$Cache = @{})
        $parameters = @{ Path = (Join-Path $script:Tree $Relative); Cache = $Cache }
        if ($null -ne $Settings) { $parameters.Settings = $Settings }
        InModuleScope IntuneScriptLab -Parameters $parameters {
            $splat = @{ Path = $Path; Cache = $Cache }
            if ($null -ne $Settings) { $splat.Settings = $Settings }
            Get-IslSetting @splat
        }
    }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Get-IslSetting' -Tag 'Unit', 'Private' {

    It 'finds the settings file above a script and reads every key' {
        $settings = Get-Setting 'Intune\Remediations\Widget\Detect.ps1'
        $settings.PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.Settings'
        $settings.Source | Should-Be (Join-Path $script:Tree 'IntuneScriptLab.settings.psd1')
        $settings.ExcludeRule | Should-BeCollection @('IslAssumedContext')
        $settings.MinimumSeverity | Should-Be 'Warning'
        $settings.Severity['IslLongSleep'] | Should-Be 'Information'
        $settings.Context | Should-Be 'System'
        $settings.ScriptType | Should-BeNull
        $settings.EnforceSignatureCheck | Should-BeNull
    }

    It 'lets the nearest file win and does not merge with the one above' {
        $settings = Get-Setting 'Intune\Win32\App\Detect.ps1'
        $settings.Source | Should-Be (Join-Path $script:Tree 'Intune\Win32\IntuneScriptLab.settings.psd1')
        $settings.ScriptType | Should-Be 'Win32Detection'
        $settings.EnforceSignatureCheck | Should-BeTrue
        @($settings.ExcludeRule).Count | Should-Be 0
        $settings.MinimumSeverity | Should-BeNull
    }

    It 'returns an empty settings object when no file is found' {
        $far = Join-Path $TestDrive 'elsewhere'
        $null = New-Item -ItemType Directory -Path $far -Force
        Set-Content (Join-Path $far 'Run.ps1') 'exit 0'
        $settings = InModuleScope IntuneScriptLab -Parameters @{ Path = (Join-Path $far 'Run.ps1') } {
            Get-IslSetting -Path $Path
        }
        $settings.Source | Should-Be ''
        @($settings.ExcludeRule).Count | Should-Be 0
        $settings.Severity.Count | Should-Be 0
    }

    It 'searches a folder once when given a cache' {
        $cache = @{}
        $first = Get-Setting 'Intune\Remediations\Widget\Detect.ps1' -Cache $cache
        $cache.Count | Should-Be 1
        $again = Get-Setting 'Intune\Remediations\Widget\Detect.ps1' -Cache $cache
        $again.Source | Should-Be $first.Source
        $cache.Count | Should-Be 1
    }

    It 'takes a file path or a hashtable instead of searching, and an empty hashtable as none' {
        $explicit = Join-Path $script:Tree 'Intune\Win32\IntuneScriptLab.settings.psd1'
        (Get-Setting 'Other\Run.ps1' -Settings $explicit).ScriptType | Should-Be 'Win32Detection'
        $table = Get-Setting 'Other\Run.ps1' -Settings @{ ExcludeRule = 'IslLongSleep'; Architecture = 'arm64' }
        $table.Source | Should-Be '-Settings'
        $table.ExcludeRule | Should-BeCollection @('IslLongSleep')
        $table.Architecture | Should-Be 'arm64'
        (Get-Setting 'Intune\Remediations\Widget\Detect.ps1' -Settings @{}).Source | Should-Be '-Settings'
        @((Get-Setting 'Intune\Remediations\Widget\Detect.ps1' -Settings @{}).ExcludeRule).Count | Should-Be 0
    }

    It 'rejects values outside the sets and warns about keys it does not know' {
        { Get-Setting 'Other\Run.ps1' -Settings @{ MinimumSeverity = 'Fatal' } } |
            Should-Throw -ExceptionMessage '*MinimumSeverity must be one of*'
        { Get-Setting 'Other\Run.ps1' -Settings @{ ScriptType = 'Script' } } |
            Should-Throw -ExceptionMessage '*ScriptType must be one of*'
        { Get-Setting 'Other\Run.ps1' -Settings @{ Severity = @{ IslLongSleep = 'Loud' } } } |
            Should-Throw -ExceptionMessage '*Severity for IslLongSleep*'
        { Get-Setting 'Other\Run.ps1' -Settings @{ Context = 'Admin' } } | Should-Throw
        { Get-Setting 'Other\Run.ps1' -Settings @{ Architecture = 'ia64' } } | Should-Throw
        $result = InModuleScope IntuneScriptLab -Parameters @{ Path = (Join-Path $script:Tree 'Other\Run.ps1') } {
            Get-IslSetting -Path $Path -Settings @{ Colour = 'blue' } -WarningVariable w 3>$null
            $w
        }
        "$result" | Should-BeLikeString '*Unknown settings key(s)*Colour*'
    }
}
