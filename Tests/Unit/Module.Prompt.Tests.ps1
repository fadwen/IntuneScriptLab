#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    No test may make PowerShell ask for input. A call that leaves out a mandatory parameter is an
    error only in a host that cannot prompt, as a CI step is. At a console, and wherever the
    standard input stays open, PowerShell asks for the value and the whole suite waits for an
    answer (#93). No test of behaviour shows that where the suites usually run, so the test files
    are checked on their syntax trees: no call to a function of the module without each of its
    mandatory parameters.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }

    function Find-PromptingCall {
        <#
        .SYNOPSIS
            Lists the calls in a syntax tree that leave out a mandatory parameter of a known command.

        .DESCRIPTION
            A call is reported when no parameter set of the command has all of its mandatory
            parameters given, by name, by an unambiguous prefix of the name, by an alias or by
            position. A call with a splat is not judged, because the splat can carry anything, and
            neither is a call that takes its input from a pipeline.

        .PARAMETER ScriptAst
            The syntax tree to search.

        .PARAMETER Command
            The commands to look for, by name.

        .PARAMETER Label
            What to call the tree in the result, such as the name of its file.

        .EXAMPLE
            Find-PromptingCall -ScriptAst $tree -Command $script:Commands -Label 'Some.Tests.ps1'

            The calls in the tree that would make PowerShell prompt.

        .INPUTS
            None.

        .OUTPUTS
            System.String. One line for each call: the label, the line, the command and what is missing.
        #>
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [Parameter(Mandatory)]
            [System.Management.Automation.Language.Ast]$ScriptAst,

            [Parameter(Mandatory)]
            [hashtable]$Command,

            [Parameter(Mandatory)]
            [string]$Label
        )

        $parameterType = [System.Management.Automation.Language.CommandParameterAst]
        $commandType = [System.Management.Automation.Language.CommandAst]
        $calls = $ScriptAst.FindAll({ param($node) $node -is $commandType }, $true)
        foreach ($call in $calls) {
            $name = $call.GetCommandName()
            if (-not $name -or -not $Command.ContainsKey($name)) {
                continue
            }
            $target = $Command[$name]
            $elements = @($call.CommandElements | Select-Object -Skip 1)
            $hasSplat = @($elements | Where-Object {
                    $_ -is [System.Management.Automation.Language.VariableExpressionAst] -and $_.Splatted
                }).Count -gt 0
            $pipeline = $call.Parent
            $isPiped = $pipeline -is [System.Management.Automation.Language.PipelineAst] -and
                $pipeline.PipelineElements.Count -gt 1 -and $pipeline.PipelineElements[0] -ne $call
            if ($hasSplat -or $isPiped) {
                continue
            }

            # Which parameters the call names, and how many arguments are left for the positions
            $named = [System.Collections.Generic.List[string]]::new()
            $positionalCount = 0
            $index = 0
            while ($index -lt $elements.Count) {
                $element = $elements[$index]
                $index++
                if ($element -isnot $parameterType) {
                    $positionalCount++
                    continue
                }
                $matching = @($target.Parameters.Values | Where-Object {
                        $_.Name -eq $element.ParameterName -or $_.Aliases -contains $element.ParameterName
                    })
                if ($matching.Count -eq 0) {
                    $prefix = "$($element.ParameterName)*"
                    $matching = @($target.Parameters.Values | Where-Object { $_.Name -like $prefix })
                }
                if ($matching.Count -ne 1) {
                    continue
                }
                $named.Add($matching[0].Name)
                $takesArgument = $matching[0].ParameterType -ne [switch] -and $null -eq $element.Argument
                if ($takesArgument) {
                    $index++
                }
            }

            $isComplete = $false
            $missingNames = foreach ($set in $target.ParameterSets) {
                $missing = @($set.Parameters | Where-Object {
                        $_.IsMandatory -and $named -notcontains $_.Name -and
                        -not ($_.Position -ge 0 -and $_.Position -lt $positionalCount)
                    } | ForEach-Object { $_.Name })
                if ($missing.Count -eq 0) {
                    $isComplete = $true
                }
                $missing
            }
            if (-not $isComplete) {
                $missingText = @($missingNames | Sort-Object -Unique) -join ', '
                "${Label}:$($call.Extent.StartLineNumber) $name without $missingText"
            }
        }
    }

    $script:Commands = @{}
    $functions = InModuleScope IntuneScriptLab { Get-Command -Module IntuneScriptLab -CommandType Function }
    foreach ($function in $functions) {
        $script:Commands[$function.Name] = $function
    }

    $testFolders = @(
        (Join-Path $script:ModuleRoot 'Tests')
        (Join-Path (Join-Path $script:ModuleRoot 'Validation') 'Tests')
    )
    $script:TestFiles = @(Get-ChildItem -Path $testFolders -Recurse -Filter '*.Tests.ps1' -File)
    $script:Prompting = @(
        foreach ($file in $script:TestFiles) {
            $tree = [System.Management.Automation.Language.Parser]::ParseFile(
                $file.FullName, [ref]$null, [ref]$null)
            Find-PromptingCall -ScriptAst $tree -Command $script:Commands -Label $file.Name
        }
    )
}

Describe 'Calls in the test files that would make PowerShell prompt' -Tag 'Unit', 'Contract' {

    It 'reads the test files and knows the module''s functions, the private ones too' {
        # Guards the test below against a scan that had nothing to check
        $script:TestFiles.Count | Should-BeGreaterThan 50
        $script:Commands.ContainsKey('Test-IntuneScript') | Should-BeTrue
        $script:Commands.ContainsKey('New-IslFinding') | Should-BeTrue
    }

    It 'has no call to a function of the module without each of its mandatory parameters' {
        $script:Prompting | Should-BeCollection @()
    }

    It 'reports <Reason>' -ForEach @(
        @{
            Reason = 'a call that names three of four mandatory parameters'
            Text = 'New-IslFinding -RuleName R -Severity Error -Message m'
            Expected = @('sample:1 New-IslFinding without Context')
        }
        @{
            Reason = 'a call inside a script block that is handed to an assertion'
            Text = "`n{ Invoke-IslScriptRun -Architecture x86 } | Should-Throw"
            Expected = @('sample:2 Invoke-IslScriptRun without Path')
        }
        @{
            Reason = 'nothing for a call that gives the parameter by position'
            Text = 'Invoke-IntuneDetectionTest C:\lab\detect.ps1 -Context User'
            Expected = @()
        }
        @{
            Reason = 'nothing for a call that gives the parameter by a prefix of its name, after a switch'
            Text = 'Compare-IntuneDeployedScript -Verbose -Pa C:\lab'
            Expected = @()
        }
        @{
            Reason = 'nothing for a call with a splat'
            Text = 'New-IslFinding @findingSplat -RuleName R'
            Expected = @()
        }
        @{
            Reason = 'nothing for a call that takes its input from the pipeline'
            Text = "'C:\lab\detect.ps1' | Invoke-IntuneDetectionTest"
            Expected = @()
        }
    ) {
        $tree = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null)

        $found = @(Find-PromptingCall -ScriptAst $tree -Command $script:Commands -Label 'sample')

        $found | Should-BeCollection -Count $Expected.Count
        for ($index = 0; $index -lt $Expected.Count; $index++) {
            $found[$index] | Should-Be $Expected[$index]
        }
    }
}
