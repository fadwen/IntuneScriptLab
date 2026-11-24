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
        $recordSplat = @{
            Message = "The PSScriptAnalyzer rule module is missing from the module at $moduleBase"
            ErrorId = 'AnalyzerRulesMissing'
            Category = [System.Management.Automation.ErrorCategory]::ObjectNotFound
            TargetObject = $path
            ExceptionType = [System.IO.FileNotFoundException]
        }
        $PSCmdlet.ThrowTerminatingError((New-IslErrorRecord @recordSplat))
    }
    $path
}
