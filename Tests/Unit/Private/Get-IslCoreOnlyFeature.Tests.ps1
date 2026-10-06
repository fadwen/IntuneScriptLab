#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The table IslPowerShell7Syntax reports from, held against the two hosts themselves: each entry
    must be missing from Windows PowerShell 5.1 and present in PowerShell 7. Both hosts are asked
    as child processes, so the test gives the same answer whichever one runs it; it is skipped
    where either host is missing.
#>

BeforeDiscovery {
    $script:BothHosts = [bool](Get-Command powershell.exe -ErrorAction SilentlyContinue) -and
        [bool](Get-Command pwsh.exe -ErrorAction SilentlyContinue)
}

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    $script:Table = InModuleScope IntuneScriptLab { Get-IslCoreOnlyFeature }

    # What each host says about the table: for every command whether it exists, for every parameter
    # whether its command has it, and for every value whether the parameter's ValidateSet takes it
    # (no ValidateSet means the value is not refused there)
    $probe = {
        param($Json)
        $table = $Json | ConvertFrom-Json
        $result = @{ Commands = @{}; Parameters = @{}; Values = @{} }
        foreach ($name in $table.Commands) {
            $result.Commands[$name] = [bool](Get-Command -Name $name -ErrorAction SilentlyContinue)
        }
        foreach ($entry in $table.Parameters) {
            $command = Get-Command -Name $entry.Command -ErrorAction SilentlyContinue
            foreach ($parameter in $entry.Parameters) {
                $result.Parameters["$($entry.Command) -$parameter"] =
                    [bool]($command -and $command.Parameters.ContainsKey($parameter))
            }
        }
        foreach ($entry in $table.Values) {
            $command = Get-Command -Name $entry.Command -ErrorAction SilentlyContinue
            $set = @()
            if ($command -and $command.Parameters.ContainsKey($entry.Parameter)) {
                $set = @($command.Parameters[$entry.Parameter].Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
                    ForEach-Object { $_.ValidValues })
            }
            foreach ($value in $entry.Values) {
                $result.Values["$($entry.Command) -$($entry.Parameter) $value"] =
                    if ($set.Count) { [bool]($set -contains $value) } else { [bool]$command }
            }
        }
        $result | ConvertTo-Json -Depth 4 -Compress
    }
    $flat = [pscustomobject]@{
        Commands   = @($script:Table.Commands)
        Parameters = @(foreach ($command in $script:Table.Parameters.Keys) {
                @{ Command = $command; Parameters = @($script:Table.Parameters[$command]) }
            }) + @(@{ Command = 'ForEach-Object'; Parameters = @('Parallel') })
        Values     = @(foreach ($command in $script:Table.Values.Keys) {
                foreach ($parameter in $script:Table.Values[$command].Keys) {
                    $values = @($script:Table.Values[$command][$parameter])
                    @{ Command = $command; Parameter = $parameter; Values = $values }
                }
            })
    }
    $json = $flat | ConvertTo-Json -Depth 5 -Compress
    $command = "& { $($probe.ToString()) } '$($json.Replace("'", "''"))'"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    function script:Get-HostAnswer {
        param([string]$Exe, [string]$Command)
        $raw = & $Exe -NoProfile -NonInteractive -EncodedCommand $Command 2>&1
        ($raw | Where-Object { "$_".StartsWith('{') } | Select-Object -Last 1) | ConvertFrom-Json
    }
    # Discovery-time variables do not reach the run, so the lookup is repeated here
    $script:BothHosts = [bool](Get-Command powershell.exe -ErrorAction SilentlyContinue) -and
        [bool](Get-Command pwsh.exe -ErrorAction SilentlyContinue)
    if ($script:BothHosts) {
        $script:Desktop = Get-HostAnswer 'powershell.exe' $encoded
        $script:Core = Get-HostAnswer 'pwsh.exe' $encoded
    }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Get-IslCoreOnlyFeature' -Tag 'Unit', 'Private' {

    It 'returns the three tables' {
        $script:Table.PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.CoreOnlyFeature'
        $script:Table.Commands.Count | Should-BeGreaterThan 5
        $script:Table.Parameters.Keys.Count | Should-BeGreaterThan 5
        $script:Table.Values['Out-File'].Encoding | Should-ContainCollection 'utf8NoBOM'
    }

    Context 'Against both hosts' -Skip:(-not $script:BothHosts) {
        It 'every listed command is missing from Windows PowerShell 5.1 and present in PowerShell 7' {
            $wrong = @(foreach ($name in $script:Table.Commands) {
                    if ($script:Desktop.Commands.$name) { "$name exists in 5.1" }
                    if (-not $script:Core.Commands.$name) { "$name is missing from 7" }
                })
            $wrong | Should-BeCollection @()
        }

        It 'every listed parameter is missing from the 5.1 command and present on the 7 one' {
            $keys = @($script:Core.Parameters.PSObject.Properties.Name)
            $keys.Count | Should-BeGreaterThan 30
            $wrong = @(foreach ($key in $keys) {
                    if ($script:Desktop.Parameters.$key) { "$key exists in 5.1" }
                    if (-not $script:Core.Parameters.$key) { "$key is missing from 7" }
                })
            $wrong | Should-BeCollection @()
        }

        It 'every listed value is refused by the 5.1 parameter and taken by the 7 one' {
            $keys = @($script:Core.Values.PSObject.Properties.Name)
            $keys.Count | Should-BeGreaterThan 0
            $wrong = @(foreach ($key in $keys) {
                    if ($script:Desktop.Values.$key) { "$key is accepted by 5.1" }
                    if (-not $script:Core.Values.$key) { "$key is refused by 7" }
                })
            $wrong | Should-BeCollection @()
        }
    }
}
