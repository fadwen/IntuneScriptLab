#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The one finding shape every rule reports through.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
    $script:Path = New-TestScript 'Detect-Shape.ps1' "Write-Output 'x'`nexit 2"
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'New-IslFinding' -Tag 'Unit', 'Private' {

    Context 'Parameter Validation' {
        It 'requires a rule name, a severity from the set, a message and a context' {
            InModuleScope IntuneScriptLab -Parameters @{ Path = $script:Path } {
                $scriptContext = Get-IslScriptContext -Path $Path
                { New-IslFinding -RuleName R -Severity Fatal -Message m -Context $scriptContext } | Should-Throw
                { New-IslFinding -RuleName R -Severity Error -Message m } | Should-Throw
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
