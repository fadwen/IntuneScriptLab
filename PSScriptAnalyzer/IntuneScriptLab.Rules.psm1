#Requires -Version 5.1
<#
    PSScriptAnalyzer custom rules that wrap IntuneScriptLab's analysis, one Measure-* function per
    IntuneScriptLab rule, so the checks run under Invoke-ScriptAnalyzer next to the built-in rules:

        Invoke-ScriptAnalyzer -Path . -Recurse -CustomRulePath (Get-IntuneAnalyzerRulePath) -IncludeDefaultRules

    or from a PSScriptAnalyzerSettings.psd1 with CustomRulePath set to this file's path.

    PSScriptAnalyzer discovers rules by parsing this file for functions with an AST parameter, so
    the functions are written out rather than generated; the module's contract test keeps them in
    step with the rule list. PSScriptAnalyzer invokes a rule once for every ScriptBlockAst in a
    file (the root, each function body, each script block), so every rule runs Test-IntuneScript
    only on the root and the result is cached per file for the rules that follow. A
    -ScriptDefinition has no file; its text goes to a temporary .ps1 so the script type can still
    come from a '# IntuneScriptLab: ScriptType=...' directive.
#>

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '..\IntuneScriptLab.psd1') -ErrorAction Stop

$script:AnalysisCache = [hashtable]::Synchronized(@{})

function Get-IslAnalysis {
    <#
    .SYNOPSIS
        Runs Test-IntuneScript once per file (or script definition) and caches the findings.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst
    )
    $file = $ScriptBlockAst.Extent.File
    if ($file) {
        $item = Get-Item -LiteralPath $file -ErrorAction Stop
        $key = "$($item.FullName)|$($item.LastWriteTimeUtc.Ticks)|$($item.Length)"
        if (-not $script:AnalysisCache.ContainsKey($key)) {
            $script:AnalysisCache[$key] = @(Test-IntuneScript -Path $item.FullName)
        }
        return $script:AnalysisCache[$key]
    }

    # No file: the text of the definition, written where the analyzer can read it as a script
    $text = $ScriptBlockAst.Extent.Text
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = [System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text)))
    }
    finally { $sha.Dispose() }
    $key = "definition|$($hash -replace '-', '')"
    if (-not $script:AnalysisCache.ContainsKey($key)) {
        $folder = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'IntuneScriptLab'
        $null = New-Item -ItemType Directory -Path $folder -Force
        $temp = Join-Path -Path $folder -ChildPath "definition-$([guid]::NewGuid().ToString('N')).ps1"
        try {
            [System.IO.File]::WriteAllText($temp, $text, [System.Text.UTF8Encoding]::new($true))
            $script:AnalysisCache[$key] = @(Test-IntuneScript -Path $temp)
        }
        finally {
            Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        }
    }
    $script:AnalysisCache[$key]
}

function Get-IslRuleRecord {
    <#
    .SYNOPSIS
        The PSScriptAnalyzer records for one IntuneScriptLab rule on one script block.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Rule,

        [Parameter(Mandatory)]
        [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst
    )
    # Nested script blocks are part of the same file; the root carries the analysis
    if ($null -ne $ScriptBlockAst.Parent) { return }
    $file = $ScriptBlockAst.Extent.File
    foreach ($finding in (Get-IslAnalysis -ScriptBlockAst $ScriptBlockAst)) {
        if ($finding.RuleName -ne $Rule) { continue }
        $extent = if ($finding.Line -gt 0) {
            $lines = @("$($finding.Text)" -split "`r?`n")
            $endLine = $finding.Line + $lines.Count - 1
            $endColumn = if ($lines.Count -eq 1) { $finding.Column + $lines[0].Length }
            else { $lines[-1].Length + 1 }
            $start = [System.Management.Automation.Language.ScriptPosition]::new($file, $finding.Line,
                $finding.Column, $lines[0])
            $end = [System.Management.Automation.Language.ScriptPosition]::new($file, $endLine, $endColumn,
                $lines[-1])
            [System.Management.Automation.Language.ScriptExtent]::new($start, $end)
        }
        else { $ScriptBlockAst.Extent }
        $message = if ($finding.Evidence) { "$($finding.Message) [Observed: $($finding.Evidence)]" }
        else { $finding.Message }
        [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
            Message  = $message
            Extent   = $extent
            RuleName = "Measure-$Rule"
            Severity = $finding.Severity
        }
    }
}

function Measure-IslPowerShell7Syntax {
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst
    )
    Get-IslRuleRecord -Rule 'IslPowerShell7Syntax' -ScriptBlockAst $ScriptBlockAst
}

function Measure-IslEncodingIssue {
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst
    )
    Get-IslRuleRecord -Rule 'IslEncodingIssue' -ScriptBlockAst $ScriptBlockAst
}

function Measure-IslInteractiveCall {
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst
    )
    Get-IslRuleRecord -Rule 'IslInteractiveCall' -ScriptBlockAst $ScriptBlockAst
}

function Measure-IslExitCodeIssue {
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst
    )
    Get-IslRuleRecord -Rule 'IslExitCodeIssue' -ScriptBlockAst $ScriptBlockAst
}

function Measure-IslOutputIssue {
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst
    )
    Get-IslRuleRecord -Rule 'IslOutputIssue' -ScriptBlockAst $ScriptBlockAst
}

function Measure-IslContextIssue {
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst
    )
    Get-IslRuleRecord -Rule 'IslContextIssue' -ScriptBlockAst $ScriptBlockAst
}

function Measure-IslArchitectureIssue {
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst
    )
    Get-IslRuleRecord -Rule 'IslArchitectureIssue' -ScriptBlockAst $ScriptBlockAst
}

function Measure-IslArm64Assumption {
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst
    )
    Get-IslRuleRecord -Rule 'IslArm64Assumption' -ScriptBlockAst $ScriptBlockAst
}

function Measure-IslRebootCommand {
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst
    )
    Get-IslRuleRecord -Rule 'IslRebootCommand' -ScriptBlockAst $ScriptBlockAst
}

function Measure-IslRelativePath {
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst
    )
    Get-IslRuleRecord -Rule 'IslRelativePath' -ScriptBlockAst $ScriptBlockAst
}

function Measure-IslLongSleep {
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst
    )
    Get-IslRuleRecord -Rule 'IslLongSleep' -ScriptBlockAst $ScriptBlockAst
}

function Measure-IslSignatureIssue {
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst
    )
    Get-IslRuleRecord -Rule 'IslSignatureIssue' -ScriptBlockAst $ScriptBlockAst
}

function Measure-IslAssumedContext {
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst
    )
    Get-IslRuleRecord -Rule 'IslAssumedContext' -ScriptBlockAst $ScriptBlockAst
}
function Measure-IslExecutionPolicyCall {
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst
    )
    Get-IslRuleRecord -Rule 'IslExecutionPolicyCall' -ScriptBlockAst $ScriptBlockAst
}

function Measure-IslModuleDependency {
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst
    )
    Get-IslRuleRecord -Rule 'IslModuleDependency' -ScriptBlockAst $ScriptBlockAst
}

function Measure-IslScriptSize {
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst
    )
    Get-IslRuleRecord -Rule 'IslScriptSize' -ScriptBlockAst $ScriptBlockAst
}

Export-ModuleMember -Function @(
    'Measure-IslPowerShell7Syntax'
    'Measure-IslEncodingIssue'
    'Measure-IslInteractiveCall'
    'Measure-IslExitCodeIssue'
    'Measure-IslOutputIssue'
    'Measure-IslContextIssue'
    'Measure-IslArchitectureIssue'
    'Measure-IslArm64Assumption'
    'Measure-IslRebootCommand'
    'Measure-IslRelativePath'
    'Measure-IslLongSleep'
    'Measure-IslSignatureIssue'
    'Measure-IslAssumedContext'
    'Measure-IslExecutionPolicyCall'
    'Measure-IslModuleDependency'
    'Measure-IslScriptSize'
)
