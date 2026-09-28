function Get-IntuneAnalyzerRulePath {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Returns IntuneScriptLab's PSScriptAnalyzer rule module, for -CustomRulePath.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $moduleBase = $MyInvocation.MyCommand.Module.ModuleBase
    $folder = Join-Path -Path $moduleBase -ChildPath 'PSScriptAnalyzer'
    $path = Join-Path -Path $folder -ChildPath 'IntuneScriptLab.Rules.psm1'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "The PSScriptAnalyzer rule module is missing from the module at $moduleBase"
    }
    $path
}
