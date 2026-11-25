#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The reduction of a remediation's output to what the portal shows, as observed (REM-OUT-STREAMS,
    REM-OUT-LONG, REM-ERR-LONG): the last stdout line, capped at its last 2,048 characters, and the
    whole stderr text capped the same way.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')

    function Get-IntuneOutput {
        <#
        .SYNOPSIS
            Gets the output that the portal shows for the given streams of a run.

        .DESCRIPTION
            Runs Get-IslIntuneOutput inside the module, where the private function can be reached,
            with empty streams and the limit of 2,048 characters unless the test gives others.

        .PARAMETER StdOut
            The standard output of the run.

        .PARAMETER StdErr
            The standard error of the run.

        .PARAMETER Limit
            The number of characters that each stream is capped at.

        .EXAMPLE
            Get-IntuneOutput -StdOut "one`r`ntwo`r`n"

            Returns the output reduced to its last line, two.

        .INPUTS
            None.

        .OUTPUTS
            IntuneScriptLab.IntuneOutput. The output and the error text as the portal shows them.
        #>
        [CmdletBinding()]
        [OutputType('IntuneScriptLab.IntuneOutput')]
        param(
            [string]$StdOut = '',

            [string]$StdErr = '',

            [int]$Limit = 2048
        )

        $parameters = @{ StdOut = $StdOut; StdErr = $StdErr; Limit = $Limit }
        InModuleScope IntuneScriptLab -Parameters $parameters {
            Get-IslIntuneOutput -StdOut $StdOut -StdErr $StdErr -Limit $Limit
        }
    }
}

Describe 'Get-IslIntuneOutput' -Tag 'Unit', 'Private' {

    Context 'Parameter Validation' {
        It 'accepts empty streams' {
            $result = Get-IntuneOutput
            $result.Output | Should-Be ''
            $result.Error | Should-Be ''
            $result.DroppedLines | Should-Be 0
            $result.PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.IntuneOutput'
        }
    }

    Context 'Core Functionality' {
        It 'keeps only the last non-empty stdout line and counts the dropped ones' {
            $result = Get-IntuneOutput -StdOut "one`r`ntwo`r`n`r`nthree`r`n"
            $result.Output | Should-Be 'three'
            $result.DroppedLines | Should-Be 2
            $result.OutputTruncated | Should-BeFalse
        }

        It 'keeps the last <Limit> characters of that line and flags the truncation' {
            $result = Get-IntuneOutput -StdOut ('a' * 10 + 'b' * 2048)
            $result.Output.Length | Should-Be 2048
            $result.Output | Should-BeLikeString 'bbbb*'
            $result.OutputTruncated | Should-BeTrue
            (Get-IntuneOutput -StdOut 'abcdef' -Limit 4).Output | Should-Be 'cdef'
        }

        It 'keeps the whole stderr text, trailing newlines trimmed, capped the same way' {
            $result = Get-IntuneOutput -StdErr "first`r`nsecond`r`n"
            $result.Error | Should-Be "first`r`nsecond"
            $result.ErrorTruncated | Should-BeFalse
            $long = Get-IntuneOutput -StdErr ('e' * 3000)
            $long.Error.Length | Should-Be 2048
            $long.ErrorTruncated | Should-BeTrue
        }

        It 'treats a single line without a newline as the last line' {
            (Get-IntuneOutput -StdOut 'only').Output | Should-Be 'only'
        }
    }
}
