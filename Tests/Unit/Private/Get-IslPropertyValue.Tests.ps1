#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The accessor for data with optional members. A Graph reply is a dictionary or an object
    depending on how it was read, and under the module's strict mode a plain read of a member that
    is not there is an error, so the same reads are checked against both shapes.
#>

BeforeDiscovery {
    $script:Shapes = @(
        @{
            Shape = 'a hashtable'
            Data = @{ id = 'rem-a'; runAs32Bit = $false; deviceCount = 0; '@odata.type' = '#policy' }
        }
        @{
            Shape = 'an ordered dictionary'
            Data = [ordered]@{ id = 'rem-a'; runAs32Bit = $false; deviceCount = 0; '@odata.type' = '#policy' }
        }
        @{
            Shape = 'an object'
            Data = [pscustomobject]@{
                id = 'rem-a'; runAs32Bit = $false; deviceCount = 0; '@odata.type' = '#policy'
            }
        }
    )
}

BeforeAll {
    if (-not (Get-Module -Name IntuneScriptLab)) {
        $moduleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $moduleRoot 'IntuneScriptLab.psd1')
    }
}

Describe 'Get-IslPropertyValue' -Tag 'Unit', 'Private' {

    Context 'Parameter Validation' {
        It 'declares Name as mandatory and lets InputObject be omitted or null' {
            InModuleScope IntuneScriptLab {
                $command = Get-Command -Name Get-IslPropertyValue
                $command | Should-HaveParameter -ParameterName 'Name' -Type ([string]) -Mandatory
                $declared = @($command.Parameters['InputObject'].Attributes |
                        Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })
                $declared.Count | Should-Be 1
                $declared[0].Mandatory | Should-BeFalse
                @(Get-IslPropertyValue -InputObject $null -Name 'id').Count | Should-Be 0
                @(Get-IslPropertyValue -Name 'id').Count | Should-Be 0
            }
        }
    }

    Context 'Core Functionality' {
        It 'reads a value from <Shape>' -ForEach $script:Shapes {
            InModuleScope IntuneScriptLab -Parameters @{ Data = $Data } {
                Get-IslPropertyValue -InputObject $Data -Name 'id' | Should-Be 'rem-a'
                Get-IslPropertyValue -InputObject $Data -Name '@odata.type' | Should-Be '#policy'
                Get-IslPropertyValue -InputObject $Data -Name 'ID' | Should-Be 'rem-a'
            }
        }

        It 'returns a value that is false or zero from <Shape>, not nothing' -ForEach $script:Shapes {
            InModuleScope IntuneScriptLab -Parameters @{ Data = $Data } {
                $flag = @(Get-IslPropertyValue -InputObject $Data -Name 'runAs32Bit')
                $flag.Count | Should-Be 1
                $flag[0] | Should-BeFalse
                $count = @(Get-IslPropertyValue -InputObject $Data -Name 'deviceCount')
                $count.Count | Should-Be 1
                $count[0] | Should-Be 0
            }
        }

        It 'returns nothing for a member that <Shape> does not have' -ForEach $script:Shapes {
            InModuleScope IntuneScriptLab -Parameters @{ Data = $Data } {
                @(Get-IslPropertyValue -InputObject $Data -Name 'remediationScriptContent').Count | Should-Be 0
                $value = Get-IslPropertyValue -InputObject $Data -Name 'remediationScriptContent'
                $value | Should-BeNull
            }
        }

        It 'reads the entry of a dictionary, never the dictionary''s own property of that name' {
            InModuleScope IntuneScriptLab {
                # Member syntax reads Count and Keys from the hashtable itself when it has no such entry
                @(Get-IslPropertyValue -InputObject @{ id = 'rem-a' } -Name 'Count').Count | Should-Be 0
                @(Get-IslPropertyValue -InputObject @{ id = 'rem-a' } -Name 'Keys').Count | Should-Be 0
                Get-IslPropertyValue -InputObject @{ id = 'rem-a'; Count = 5 } -Name 'Count' | Should-Be 5
            }
        }

        It 'reads a generic dictionary, whose Contains method PowerShell does not find by name' {
            InModuleScope IntuneScriptLab {
                # Dictionary[string, object] implements IDictionary.Contains explicitly, so a plain
                # call of that method on it fails with "Cannot find an overload"
                $generic = [System.Collections.Generic.Dictionary[string, object]]::new()
                $generic['id'] = 'rem-a'
                $generic['deviceCount'] = 0
                Get-IslPropertyValue -InputObject $generic -Name 'id' -ErrorAction Stop | Should-Be 'rem-a'
                Get-IslPropertyValue -InputObject $generic -Name 'deviceCount' -ErrorAction Stop | Should-Be 0
                @(Get-IslPropertyValue -InputObject $generic -Name 'runSchedule' -ErrorAction Stop).Count |
                    Should-Be 0
            }
        }

        It 'hands a list back as its elements, and an empty or missing list as nothing' {
            InModuleScope IntuneScriptLab {
                $page = @{ value = @(@{ id = 'a' }, @{ id = 'b' }); empty = @() }
                $items = @(Get-IslPropertyValue -InputObject $page -Name 'value')
                $items.Count | Should-Be 2
                $items[1]['id'] | Should-Be 'b'
                @(Get-IslPropertyValue -InputObject $page -Name 'empty').Count | Should-Be 0
                @(Get-IslPropertyValue -InputObject $page -Name '@odata.nextLink').Count | Should-Be 0
            }
        }

        It 'reads a property of a .NET object' {
            InModuleScope IntuneScriptLab {
                Get-IslPropertyValue -InputObject ([version]'5.1.2') -Name 'Minor' | Should-Be 1
                @(Get-IslPropertyValue -InputObject ([version]'5.1.2') -Name 'Patch').Count | Should-Be 0
            }
        }
    }

    Context 'Error Handling' {
        It 'does not fail on a missing member under the module''s strict mode, where a plain read does' {
            InModuleScope IntuneScriptLab {
                $reply = @{ id = 'rem-a' }
                { $null = $reply.runSchedule } | Should-Throw -ExceptionMessage '*runSchedule*'
                $schedule = Get-IslPropertyValue -InputObject $reply -Name 'runSchedule' -ErrorAction Stop
                $schedule | Should-BeNull
                # Reading on from a member that was not there gives nothing as well
                @(Get-IslPropertyValue -InputObject $schedule -Name 'date' -ErrorAction Stop).Count | Should-Be 0
            }
        }
    }

    Context 'Performance Requirements' {
        It 'makes 5,000 reads in less than five seconds' {
            {
                InModuleScope IntuneScriptLab {
                    $reply = @{ id = 'rem-a'; displayName = 'Fix-Widget' }
                    foreach ($index in 1..2500) {
                        $null = Get-IslPropertyValue -InputObject $reply -Name 'displayName'
                        $null = Get-IslPropertyValue -InputObject $reply -Name 'runSchedule'
                    }
                }
            } | Should-BeFasterThan '5s'
        }
    }
}
