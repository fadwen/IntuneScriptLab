#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The help and output type of every private function, and of every function in the
    PSScriptAnalyzer rule module, read from the syntax trees. Private help is
    the only documentation these functions have: PlatyPS does not see them. DOC-01 lists the
    keywords, DOC-10 the length of the synopsis, DOC-06 that .OUTPUTS names the declared type, and
    FUN-10 the output type itself.
#>

BeforeDiscovery {
    $moduleRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $isFunction = { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }
    # The PSScriptAnalyzer rule module ships with the package and has no PlatyPS help either, so
    # its functions are held to the same help as the private ones
    $rulesFolder = Join-Path -Path $moduleRoot -ChildPath 'PSScriptAnalyzer'
    $rulesModule = Join-Path -Path $rulesFolder -ChildPath 'IntuneScriptLab.Rules.psm1'
    $privateFolder = Join-Path -Path $moduleRoot -ChildPath 'Private'
    $files = @(Get-ChildItem -LiteralPath $privateFolder -Recurse -Filter '*.ps1') +
        @(Get-Item -LiteralPath $rulesModule)
    $script:Functions = foreach ($file in $files) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
        foreach ($function in $ast.FindAll($isFunction, $false)) {
            @{ Name = $function.Name; File = $file.FullName }
        }
    }
}

BeforeAll {
    # The type an [OutputType()] argument names, as .OUTPUTS writes it
    function script:Get-TypeName {
        param([string]$Argument)
        $text = $Argument.Trim()
        if ($text -match "^'(.+)'$") { return $Matches[1] }
        # Only the outer brackets go: [string[]] names System.String[], not System.String
        $inner = if ($text -match '^\[(.+)\]$') { $Matches[1] } else { $text }
        switch ($inner) {
            'void' { return 'None' }
            'object' { return 'System.Object' }
        }
        $type = $inner -as [type]
        if ($type) { return $type.FullName }
        $inner
    }

    function script:Get-Function {
        param([string]$File, [string]$Name)
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($File, [ref]$null, [ref]$null)
        $definition = [System.Management.Automation.Language.FunctionDefinitionAst]
        $functions = $ast.FindAll({ param($node) $node -is $definition }, $false)
        $functions | Where-Object -Property Name -EQ -Value $Name | Select-Object -First 1
    }
}

Describe 'Private function help' -Tag 'Unit', 'Contract' {

    It '<Name> has every help keyword and a short one-line synopsis' -ForEach $script:Functions {
        $function = Get-Function -File $File -Name $Name
        $help = $function.GetHelpContent()

        $help | Should-NotBeNull -Because "$Name needs comment-based help"
        $synopsis = $help.Synopsis.Trim()
        $synopsis.Contains("`n") | Should-BeFalse -Because "the synopsis of $Name is one line"
        $synopsis.Length | Should-BeLessThanOrEqual 80 -Because "the synopsis of $Name is 80 characters at most"
        $help.Description | Should-NotBeNull -Because "$Name needs a .DESCRIPTION"
        $help.Examples.Count | Should-BeGreaterThan 0 -Because "$Name needs an .EXAMPLE"
        $help.Inputs.Count | Should-BeGreaterThan 0 -Because "$Name needs .INPUTS"
        $help.Outputs.Count | Should-BeGreaterThan 0 -Because "$Name needs .OUTPUTS"
    }

    It '<Name> documents every parameter' -ForEach $script:Functions {
        $function = Get-Function -File $File -Name $Name
        $parameters = @(if ($function.Body.ParamBlock) {
                $function.Body.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }
            })
        $documented = @($function.GetHelpContent().Parameters.Keys)

        @($parameters | Where-Object { $_ -notin $documented }) | Should-BeCollection @()
    }

    It '<Name> declares its output type, and .OUTPUTS names it' -ForEach $script:Functions {
        $function = Get-Function -File $File -Name $Name
        $declared = @($function.Body.ParamBlock.Attributes | Where-Object { $_.TypeName.Name -eq 'OutputType' })

        $declared | Should-BeCollection -Count 1 -Because "$Name declares [OutputType()]"
        $arguments = @($declared[0].PositionalArguments | ForEach-Object { $_.Extent.Text })
        @($arguments | Where-Object { $_ -match '(?i)^\[(System\.Management\.Automation\.)?PSCustomObject\]$' }) |
            Should-BeCollection @() -Because 'FUN-10 rules out [OutputType([PSCustomObject])]'
        # Each .OUTPUTS entry starts with the type it names, followed by a full stop, comma or colon
        $documented = @($function.GetHelpContent().Outputs | ForEach-Object {
                ($_.Trim() -split '\s+')[0].TrimEnd('.', ',', ':')
            })
        foreach ($argument in $arguments) {
            $typeName = Get-TypeName -Argument $argument
            $documented | Should-ContainCollection $typeName -Because ".OUTPUTS of $Name names $argument"
        }
    }
}
