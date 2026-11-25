#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The artifactLocation of a SARIF result: relative to the root where it can be, absolute
    otherwise.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    function ConvertTo-Location {
        <#
        .SYNOPSIS
            Converts a path to its SARIF artifactLocation with the private function.

        .DESCRIPTION
            ConvertTo-IslSarifLocation is private, so the test reaches it through InModuleScope.

        .PARAMETER FilePath
            The path of the analyzed file.

        .PARAMETER RootPath
            The root that a relative URI is taken from. An empty string stands for the file system
            root of Linux.

        .EXAMPLE
            ConvertTo-Location 'C:\repo\Detect.ps1' 'C:\repo'

            Returns the location of Detect.ps1 relative to C:\repo.

        .INPUTS
            None.

        .OUTPUTS
            System.Collections.Specialized.OrderedDictionary. The uri and, below the root, uriBaseId.
        #>
        [CmdletBinding()]
        [OutputType([System.Collections.Specialized.OrderedDictionary])]
        param(
            [string]$FilePath,

            [string]$RootPath
        )

        $parameters = @{ FilePath = $FilePath; RootPath = $RootPath }
        $scope = @{ Parameters = $parameters }
        InModuleScope IntuneScriptLab -Parameters $scope { ConvertTo-IslSarifLocation @Parameters }
    }
}

Describe 'ConvertTo-IslSarifLocation' -Tag 'Unit', 'Private' {

    Context 'Parameter Validation' {
        It 'needs the path and the root' {
            $command = InModuleScope IntuneScriptLab { Get-Command -Name ConvertTo-IslSarifLocation }
            $command | Should-HaveParameter -ParameterName FilePath -Type ([string]) -Mandatory
            $command | Should-HaveParameter -ParameterName RootPath -Type ([string]) -Mandatory
        }
    }

    Context 'Core Functionality' {
        It 'gives a path below the root as a relative URI with forward slashes and the source root base' {
            $location = ConvertTo-Location 'C:\repo\Remediations\A\Detect.ps1' 'C:\repo'

            $location['uri'] | Should-Be 'Remediations/A/Detect.ps1'
            $location['uriBaseId'] | Should-Be '%SRCROOT%'
        }

        It 'escapes each segment of the relative URI' {
            $location = ConvertTo-Location 'C:\repo\My Scripts\Detect #1.ps1' 'C:\repo'

            $location['uri'] | Should-Be 'My%20Scripts/Detect%20%231.ps1'
        }

        It 'compares the path with the root without regard to letter case' {
            $location = ConvertTo-Location 'c:\REPO\Detect.ps1' 'C:\repo'

            $location['uri'] | Should-Be 'Detect.ps1'
        }

        It 'gives a path outside the root as an absolute file URI with no base' {
            $location = ConvertTo-Location 'D:\elsewhere\Detect.ps1' 'C:\repo'

            $location['uri'] | Should-Be 'file:///D:/elsewhere/Detect.ps1'
            $location.Contains('uriBaseId') | Should-BeFalse
        }

        It 'gives a path below the file system root of Linux, an empty root, as a relative URI' {
            $location = ConvertTo-Location '/repo/Remediations/Detect.ps1' ''

            $location['uri'] | Should-Be 'repo/Remediations/Detect.ps1'
            $location['uriBaseId'] | Should-Be '%SRCROOT%'
        }
    }
}
