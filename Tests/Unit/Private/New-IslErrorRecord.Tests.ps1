#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The error record a module function ends with: an ID and a category of its own, an exception of
    the type named, and the error that caused it kept as the inner exception.
#>

BeforeAll {
    $moduleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $moduleRoot) {
        Import-Module (Join-Path $moduleRoot 'IntuneScriptLab.psd1') -Force
    }
}

Describe 'New-IslErrorRecord' -Tag 'Unit', 'Private' {

    Context 'Parameter Validation' {
        It 'declares <ParameterName> as mandatory' -ForEach @(
            @{ ParameterName = 'Message'; ParameterType = [string] }
            @{ ParameterName = 'ErrorId'; ParameterType = [string] }
            @{ ParameterName = 'Category'; ParameterType = [System.Management.Automation.ErrorCategory] }
        ) {
            InModuleScope IntuneScriptLab -Parameters @{ Name = $ParameterName; Type = $ParameterType } {
                Get-Command -Name New-IslErrorRecord |
                    Should-HaveParameter -ParameterName $Name -Type $Type -Mandatory
            }
        }
    }

    Context 'Core Functionality' {
        It 'returns a record with the ID, the category, the target and an InvalidOperationException' {
            InModuleScope IntuneScriptLab {
                $recordSplat = @{
                    Message = 'C:\out.zip exists; use -Force'
                    ErrorId = 'PathExists'
                    Category = [System.Management.Automation.ErrorCategory]::ResourceExists
                    TargetObject = 'C:\out.zip'
                }
                $record = @(New-IslErrorRecord @recordSplat)

                $record | Should-BeCollection -Count 1
                $record[0] | Should-HaveType ([System.Management.Automation.ErrorRecord])
                $record[0].FullyQualifiedErrorId | Should-Be 'PathExists'
                $record[0].CategoryInfo.Category | Should-Be 'ResourceExists'
                $record[0].TargetObject | Should-Be 'C:\out.zip'
                $record[0].Exception | Should-HaveType ([System.InvalidOperationException])
                $record[0].Exception.Message | Should-Be 'C:\out.zip exists; use -Force'
                $record[0].Exception.InnerException | Should-BeNull
            }
        }

        It 'builds the exception type named and keeps the cause as the inner exception' {
            InModuleScope IntuneScriptLab {
                $cause = [System.IO.FileNotFoundException]::new('the cause')
                $recordSplat = @{
                    Message = 'Unknown event'
                    ErrorId = 'UnknownEvent'
                    Category = [System.Management.Automation.ErrorCategory]::InvalidArgument
                    ExceptionType = [System.ArgumentException]
                    InnerException = $cause
                }
                $record = New-IslErrorRecord @recordSplat

                $record.Exception | Should-HaveType ([System.ArgumentException])
                $record.Exception.Message | Should-Be 'Unknown event'
                [object]::ReferenceEquals($record.Exception.InnerException, $cause) | Should-BeTrue
                $record.TargetObject | Should-BeNull
            }
        }

        It 'gives the error the name of the function that raises it, not its own' {
            InModuleScope IntuneScriptLab {
                function Get-ProbeFailure {
                    <#
                    .SYNOPSIS
                        Ends with a record from New-IslErrorRecord, as a module function does.

                    .DESCRIPTION
                        A failure the module detects itself is raised this way, so the test reads the ID and
                        the category that a caller sees.

                    .EXAMPLE
                        Get-ProbeFailure

                        Ends with the ProbeFailed error.

                    .INPUTS
                        None.

                    .OUTPUTS
                        None.
                    #>
                    [CmdletBinding()]
                    [OutputType([void])]
                    param()
                    $recordSplat = @{ Message = 'probe'; ErrorId = 'ProbeFailed'; Category = 'InvalidOperation' }
                    $PSCmdlet.ThrowTerminatingError((New-IslErrorRecord @recordSplat))
                }

                { Get-ProbeFailure } | Should-Throw -FullyQualifiedErrorId 'ProbeFailed,Get-ProbeFailure'
            }
        }
    }

    Context 'Error Handling' {
        It 'still returns a record for a type it cannot build: <TypeName>' -ForEach @(
            # SocketException takes an error code, not a message and a cause
            @{ TypeName = 'System.Net.Sockets.SocketException' }
            @{ TypeName = 'System.String' }
        ) {
            # The call sits in the argument of ThrowTerminatingError. An error here would end only
            # that statement, and the calling function would go on as if nothing had failed
            InModuleScope IntuneScriptLab -Parameters @{ TypeName = $TypeName } {
                $recordSplat = @{ Message = 'the message'; ErrorId = 'Any'; Category = 'InvalidOperation' }
                $record = @(New-IslErrorRecord @recordSplat -ExceptionType ([type]$TypeName) -ErrorAction Stop)

                $record | Should-BeCollection -Count 1
                $record[0].Exception | Should-HaveType ([System.InvalidOperationException])
                $record[0].Exception.Message | Should-Be 'the message'
                $record[0].FullyQualifiedErrorId | Should-Be 'Any'
            }
        }
    }
}
