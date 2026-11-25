#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The one finding shape every rule reports through.
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
    $script:Path = New-TestScript 'Detect-Shape.ps1' "Write-Output 'x'`nexit 2"
}

Describe 'New-IslFinding' -Tag 'Unit', 'Private' {

    Context 'Parameter Validation' {
        It 'requires a rule name, a severity from the set, a message and a context' {
            # Read from the command, not by leaving a parameter out: a host that can prompt asks
            # for a mandatory parameter that is missing, and the suite waits for the answer
            $command = InModuleScope IntuneScriptLab { Get-Command -Name New-IslFinding }
            foreach ($name in 'RuleName', 'Severity', 'Message', 'Context') {
                $command | Should-HaveParameter -ParameterName $name -Mandatory
            }
            InModuleScope IntuneScriptLab -Parameters @{ Path = $script:Path } {
                $scriptContext = Get-IslScriptContext -Path $Path
                { New-IslFinding -RuleName R -Severity Fatal -Message m -Context $scriptContext } | Should-Throw
            }
        }
    }

    Context 'Core Functionality' {
        It 'locates the finding from the extent and stamps the script type' {
            InModuleScope IntuneScriptLab -Parameters @{ Path = $script:Path } {
                $scriptContext = Get-IslScriptContext -Path $Path
                $exit = @(Find-IslAstNode -Ast $scriptContext.Ast -TypeName ExitStatementAst)[0]
                $islFindingSplat = @{
                    RuleName = 'IslTest'
                    Severity = 'Warning'
                    Message  = 'msg'
                    Extent   = $exit.Extent
                    Context  = $scriptContext
                    Evidence = 'seen on a device'
                }
                $finding = New-IslFinding @islFindingSplat
                $finding.PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.Finding'
                $finding.RuleName | Should-Be 'IslTest'
                $finding.Severity | Should-Be 'Warning'
                $finding.ScriptPath | Should-Be $Path
                $finding.ScriptType | Should-Be 'Detection'
                $finding.Line | Should-Be 2
                $finding.Column | Should-Be 1
                $finding.Text | Should-Be 'exit 2'
                $finding.Evidence | Should-Be 'seen on a device'
            }
        }

        It 'reports line 0 and no text for a finding about the whole script' {
            InModuleScope IntuneScriptLab -Parameters @{ Path = $script:Path } {
                $scriptContext = Get-IslScriptContext -Path $Path
                $islFindingSplat = @{
                    RuleName = 'IslTest'
                    Severity = 'Information'
                    Message  = 'm'
                    Context  = $scriptContext
                }
                $finding = New-IslFinding @islFindingSplat
                $finding.Line | Should-Be 0
                $finding.Column | Should-Be 0
                $finding.Text | Should-Be ''
            }
        }
    }
}
