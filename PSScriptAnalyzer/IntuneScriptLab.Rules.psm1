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
        Runs Test-IntuneScript once for each file or definition and keeps the findings.

    .DESCRIPTION
        PSScriptAnalyzer calls every rule once for every script block of a file, so the analysis
        is kept in a cache that the rules share. A file is keyed on its full path, its last write
        time and its length, so an edited file is analyzed again. A -ScriptDefinition has no
        file: its text is written to a temporary .ps1 with a byte order mark, so the script type
        can still come from a '# IntuneScriptLab: ScriptType=...' directive, analyzed, and
        removed; it is keyed on the SHA-256 hash of its text.

    .PARAMETER ScriptBlockAst
        The root script block of the file or definition.

    .EXAMPLE
        Get-IslAnalysis -ScriptBlockAst $ScriptBlockAst

        The findings of Test-IntuneScript for the file the block belongs to.

    .INPUTS
        None.

    .OUTPUTS
        IntuneScriptLab.Finding.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.Finding')]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst
    )
    $file = $ScriptBlockAst.Extent.File
    if ($file) {
        $item = Get-Item -LiteralPath $file -ErrorAction Stop
        $key = "$($item.FullName)|$($item.LastWriteTimeUtc.Ticks)|$($item.Length)"
        if (-not $script:AnalysisCache.ContainsKey($key)) {
            $script:AnalysisCache[$key] = @(Test-IntuneScript -Path $item.FullName -ErrorAction Stop)
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
            $script:AnalysisCache[$key] = @(Test-IntuneScript -Path $temp -ErrorAction Stop)
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
        Gets the PSScriptAnalyzer records of one IntuneScriptLab rule on a script block.

    .DESCRIPTION
        Only the root script block of a file gives records; the nested ones are part of the same
        file. Each finding of the rule, from Get-IslAnalysis, becomes one DiagnosticRecord named
        Measure-<rule>, with the finding's severity and the evidence after its message. A finding
        with a line spans the lines of its text; one without a line spans the whole script.

    .PARAMETER Rule
        The IntuneScriptLab rule name, such as IslLongSleep.

    .PARAMETER ScriptBlockAst
        The script block PSScriptAnalyzer passes.

    .EXAMPLE
        Get-IslRuleRecord -Rule 'IslLongSleep' -ScriptBlockAst $ScriptBlockAst

        A record named Measure-IslLongSleep for each long wait in the file.

    .INPUTS
        None.

    .OUTPUTS
        Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord.
    #>
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord])]
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
    <#
    .SYNOPSIS
        Reports the IslPowerShell7Syntax findings as PSScriptAnalyzer records.

    .DESCRIPTION
        A PSScriptAnalyzer custom rule for IntuneScriptLab's IslPowerShell7Syntax. Its rule,
        Find-IslPowerShell7Syntax, flags syntax, cmdlets, parameters and values that only PowerShell
        7 has. Get-IslAnalysis analyzes each file once, and Get-IslRuleRecord turns its findings of
        this rule into diagnostic records; only the root script block gives records.

    .PARAMETER ScriptBlockAst
        The script block PSScriptAnalyzer passes, once for each block of a file.

    .EXAMPLE
        $rules = Get-IntuneAnalyzerRulePath
        Invoke-ScriptAnalyzer -Path Detect.ps1 -CustomRulePath $rules -IncludeRule 'Measure-IslPowerShell7Syntax'

        The IslPowerShell7Syntax findings for Detect.ps1, as DiagnosticRecord objects.

    .INPUTS
        None.

    .OUTPUTS
        Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]
    #>
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
    <#
    .SYNOPSIS
        Reports the IslEncodingIssue findings as PSScriptAnalyzer records.

    .DESCRIPTION
        A PSScriptAnalyzer custom rule for IntuneScriptLab's IslEncodingIssue. Its rule,
        Find-IslEncodingIssue, flags files Windows PowerShell 5.1 decodes as something other than
        UTF-8. Get-IslAnalysis analyzes each file once, and Get-IslRuleRecord turns its findings of
        this rule into diagnostic records; only the root script block gives records.

    .PARAMETER ScriptBlockAst
        The script block PSScriptAnalyzer passes, once for each block of a file.

    .EXAMPLE
        $rules = Get-IntuneAnalyzerRulePath
        Invoke-ScriptAnalyzer -Path Detect.ps1 -CustomRulePath $rules -IncludeRule 'Measure-IslEncodingIssue'

        The IslEncodingIssue findings for Detect.ps1, as DiagnosticRecord objects.

    .INPUTS
        None.

    .OUTPUTS
        Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]
    #>
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
    <#
    .SYNOPSIS
        Reports the IslInteractiveCall findings as PSScriptAnalyzer records.

    .DESCRIPTION
        A PSScriptAnalyzer custom rule for IntuneScriptLab's IslInteractiveCall. Its rule,
        Find-IslInteractiveCall, flags anything that waits for a person. Get-IslAnalysis analyzes
        each file once, and Get-IslRuleRecord turns its findings of this rule into diagnostic
        records; only the root script block gives records.

    .PARAMETER ScriptBlockAst
        The script block PSScriptAnalyzer passes, once for each block of a file.

    .EXAMPLE
        $rules = Get-IntuneAnalyzerRulePath
        Invoke-ScriptAnalyzer -Path Detect.ps1 -CustomRulePath $rules -IncludeRule 'Measure-IslInteractiveCall'

        The IslInteractiveCall findings for Detect.ps1, as DiagnosticRecord objects.

    .INPUTS
        None.

    .OUTPUTS
        Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]
    #>
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
    <#
    .SYNOPSIS
        Reports the IslExitCodeIssue findings as PSScriptAnalyzer records.

    .DESCRIPTION
        A PSScriptAnalyzer custom rule for IntuneScriptLab's IslExitCodeIssue. Its rule,
        Find-IslExitCodeIssue, flags exit-code mistakes in detection and remediation scripts.
        Get-IslAnalysis analyzes each file once, and Get-IslRuleRecord turns its findings of this
        rule into diagnostic records; only the root script block gives records.

    .PARAMETER ScriptBlockAst
        The script block PSScriptAnalyzer passes, once for each block of a file.

    .EXAMPLE
        $rules = Get-IntuneAnalyzerRulePath
        Invoke-ScriptAnalyzer -Path Detect.ps1 -CustomRulePath $rules -IncludeRule 'Measure-IslExitCodeIssue'

        The IslExitCodeIssue findings for Detect.ps1, as DiagnosticRecord objects.

    .INPUTS
        None.

    .OUTPUTS
        Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]
    #>
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
    <#
    .SYNOPSIS
        Reports the IslOutputIssue findings as PSScriptAnalyzer records.

    .DESCRIPTION
        A PSScriptAnalyzer custom rule for IntuneScriptLab's IslOutputIssue. Its rule,
        Find-IslOutputIssue, flags output that Intune will drop, truncate or misread.
        Get-IslAnalysis analyzes each file once, and Get-IslRuleRecord turns its findings of this
        rule into diagnostic records; only the root script block gives records.

    .PARAMETER ScriptBlockAst
        The script block PSScriptAnalyzer passes, once for each block of a file.

    .EXAMPLE
        $rules = Get-IntuneAnalyzerRulePath
        Invoke-ScriptAnalyzer -Path Detect.ps1 -CustomRulePath $rules -IncludeRule 'Measure-IslOutputIssue'

        The IslOutputIssue findings for Detect.ps1, as DiagnosticRecord objects.

    .INPUTS
        None.

    .OUTPUTS
        Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]
    #>
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
    <#
    .SYNOPSIS
        Reports the IslContextIssue findings as PSScriptAnalyzer records.

    .DESCRIPTION
        A PSScriptAnalyzer custom rule for IntuneScriptLab's IslContextIssue. Its rule,
        Find-IslContextIssue, flags per-user places in SYSTEM scripts and privileged writes in user
        scripts. Get-IslAnalysis analyzes each file once, and Get-IslRuleRecord turns its findings
        of this rule into diagnostic records; only the root script block gives records.

    .PARAMETER ScriptBlockAst
        The script block PSScriptAnalyzer passes, once for each block of a file.

    .EXAMPLE
        $rules = Get-IntuneAnalyzerRulePath
        Invoke-ScriptAnalyzer -Path Detect.ps1 -CustomRulePath $rules -IncludeRule 'Measure-IslContextIssue'

        The IslContextIssue findings for Detect.ps1, as DiagnosticRecord objects.

    .INPUTS
        None.

    .OUTPUTS
        Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]
    #>
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
    <#
    .SYNOPSIS
        Reports the IslArchitectureIssue findings as PSScriptAnalyzer records.

    .DESCRIPTION
        A PSScriptAnalyzer custom rule for IntuneScriptLab's IslArchitectureIssue. Its rule,
        Find-IslArchitectureIssue, flags paths that WOW64 redirects when the script runs in the
        32-bit host. Get-IslAnalysis analyzes each file once, and Get-IslRuleRecord turns its
        findings of this rule into diagnostic records; only the root script block gives records.

    .PARAMETER ScriptBlockAst
        The script block PSScriptAnalyzer passes, once for each block of a file.

    .EXAMPLE
        $rules = Get-IntuneAnalyzerRulePath
        Invoke-ScriptAnalyzer -Path Detect.ps1 -CustomRulePath $rules -IncludeRule 'Measure-IslArchitectureIssue'

        The IslArchitectureIssue findings for Detect.ps1, as DiagnosticRecord objects.

    .INPUTS
        None.

    .OUTPUTS
        Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]
    #>
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
    <#
    .SYNOPSIS
        Reports the IslArm64Assumption findings as PSScriptAnalyzer records.

    .DESCRIPTION
        A PSScriptAnalyzer custom rule for IntuneScriptLab's IslArm64Assumption. Its rule,
        Find-IslArm64Assumption, flags code that equates "64-bit" with x64, which breaks on Windows
        on ARM. Get-IslAnalysis analyzes each file once, and Get-IslRuleRecord turns its findings of
        this rule into diagnostic records; only the root script block gives records.

    .PARAMETER ScriptBlockAst
        The script block PSScriptAnalyzer passes, once for each block of a file.

    .EXAMPLE
        $rules = Get-IntuneAnalyzerRulePath
        Invoke-ScriptAnalyzer -Path Detect.ps1 -CustomRulePath $rules -IncludeRule 'Measure-IslArm64Assumption'

        The IslArm64Assumption findings for Detect.ps1, as DiagnosticRecord objects.

    .INPUTS
        None.

    .OUTPUTS
        Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]
    #>
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
    <#
    .SYNOPSIS
        Reports the IslRebootCommand findings as PSScriptAnalyzer records.

    .DESCRIPTION
        A PSScriptAnalyzer custom rule for IntuneScriptLab's IslRebootCommand. Its rule,
        Find-IslRebootCommand, flags restarts and shutdowns issued from inside a script.
        Get-IslAnalysis analyzes each file once, and Get-IslRuleRecord turns its findings of this
        rule into diagnostic records; only the root script block gives records.

    .PARAMETER ScriptBlockAst
        The script block PSScriptAnalyzer passes, once for each block of a file.

    .EXAMPLE
        $rules = Get-IntuneAnalyzerRulePath
        Invoke-ScriptAnalyzer -Path Detect.ps1 -CustomRulePath $rules -IncludeRule 'Measure-IslRebootCommand'

        The IslRebootCommand findings for Detect.ps1, as DiagnosticRecord objects.

    .INPUTS
        None.

    .OUTPUTS
        Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]
    #>
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
    <#
    .SYNOPSIS
        Reports the IslRelativePath findings as PSScriptAnalyzer records.

    .DESCRIPTION
        A PSScriptAnalyzer custom rule for IntuneScriptLab's IslRelativePath. Its rule,
        Find-IslRelativePath, flags paths that depend on the working directory. Get-IslAnalysis
        analyzes each file once, and Get-IslRuleRecord turns its findings of this rule into
        diagnostic records; only the root script block gives records.

    .PARAMETER ScriptBlockAst
        The script block PSScriptAnalyzer passes, once for each block of a file.

    .EXAMPLE
        $rules = Get-IntuneAnalyzerRulePath
        Invoke-ScriptAnalyzer -Path Detect.ps1 -CustomRulePath $rules -IncludeRule 'Measure-IslRelativePath'

        The IslRelativePath findings for Detect.ps1, as DiagnosticRecord objects.

    .INPUTS
        None.

    .OUTPUTS
        Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]
    #>
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
    <#
    .SYNOPSIS
        Reports the IslLongSleep findings as PSScriptAnalyzer records.

    .DESCRIPTION
        A PSScriptAnalyzer custom rule for IntuneScriptLab's IslLongSleep. Its rule,
        Find-IslLongSleep, flags waits that hit the agent's timeout or hold up other remediations.
        Get-IslAnalysis analyzes each file once, and Get-IslRuleRecord turns its findings of this
        rule into diagnostic records; only the root script block gives records.

    .PARAMETER ScriptBlockAst
        The script block PSScriptAnalyzer passes, once for each block of a file.

    .EXAMPLE
        $rules = Get-IntuneAnalyzerRulePath
        Invoke-ScriptAnalyzer -Path Detect.ps1 -CustomRulePath $rules -IncludeRule 'Measure-IslLongSleep'

        The IslLongSleep findings for Detect.ps1, as DiagnosticRecord objects.

    .INPUTS
        None.

    .OUTPUTS
        Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]
    #>
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
    <#
    .SYNOPSIS
        Reports the IslSignatureIssue findings as PSScriptAnalyzer records.

    .DESCRIPTION
        A PSScriptAnalyzer custom rule for IntuneScriptLab's IslSignatureIssue. Its rule,
        Find-IslSignatureIssue, flags a Win32 detection script the agent refuses to run under a
        signature check. Get-IslAnalysis analyzes each file once, and Get-IslRuleRecord turns its
        findings of this rule into diagnostic records; only the root script block gives records.

    .PARAMETER ScriptBlockAst
        The script block PSScriptAnalyzer passes, once for each block of a file.

    .EXAMPLE
        $rules = Get-IntuneAnalyzerRulePath
        Invoke-ScriptAnalyzer -Path Detect.ps1 -CustomRulePath $rules -IncludeRule 'Measure-IslSignatureIssue'

        The IslSignatureIssue findings for Detect.ps1, as DiagnosticRecord objects.

    .INPUTS
        None.

    .OUTPUTS
        Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]
    #>
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
    <#
    .SYNOPSIS
        Reports the IslAssumedContext findings as PSScriptAnalyzer records.

    .DESCRIPTION
        A PSScriptAnalyzer custom rule for IntuneScriptLab's IslAssumedContext. The rule is the note
        Test-IntuneScript adds when it inferred the script type, context or architecture instead of
        being told them. Get-IslAnalysis analyzes each file once, and Get-IslRuleRecord turns its
        findings of this rule into diagnostic records; only the root script block gives records.

    .PARAMETER ScriptBlockAst
        The script block PSScriptAnalyzer passes, once for each block of a file.

    .EXAMPLE
        $rules = Get-IntuneAnalyzerRulePath
        Invoke-ScriptAnalyzer -Path Detect.ps1 -CustomRulePath $rules -IncludeRule 'Measure-IslAssumedContext'

        The IslAssumedContext findings for Detect.ps1, as DiagnosticRecord objects.

    .INPUTS
        None.

    .OUTPUTS
        Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]
    #>
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
    <#
    .SYNOPSIS
        Reports the IslExecutionPolicyCall findings as PSScriptAnalyzer records.

    .DESCRIPTION
        A PSScriptAnalyzer custom rule for IntuneScriptLab's IslExecutionPolicyCall. Its rule,
        Find-IslExecutionPolicyCall, flags Set-ExecutionPolicy, which the agent's launch makes
        redundant or harmful. Get-IslAnalysis analyzes each file once, and Get-IslRuleRecord turns
        its findings of this rule into diagnostic records; only the root script block gives records.

    .PARAMETER ScriptBlockAst
        The script block PSScriptAnalyzer passes, once for each block of a file.

    .EXAMPLE
        $rules = Get-IntuneAnalyzerRulePath
        Invoke-ScriptAnalyzer -Path Detect.ps1 -CustomRulePath $rules -IncludeRule 'Measure-IslExecutionPolicyCall'

        The IslExecutionPolicyCall findings for Detect.ps1, as DiagnosticRecord objects.

    .INPUTS
        None.

    .OUTPUTS
        Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]
    #>
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
    <#
    .SYNOPSIS
        Reports the IslModuleDependency findings as PSScriptAnalyzer records.

    .DESCRIPTION
        A PSScriptAnalyzer custom rule for IntuneScriptLab's IslModuleDependency. Its rule,
        Find-IslModuleDependency, flags modules a script needs that the agent's SYSTEM session will
        not have. Get-IslAnalysis analyzes each file once, and Get-IslRuleRecord turns its findings
        of this rule into diagnostic records; only the root script block gives records.

    .PARAMETER ScriptBlockAst
        The script block PSScriptAnalyzer passes, once for each block of a file.

    .EXAMPLE
        $rules = Get-IntuneAnalyzerRulePath
        Invoke-ScriptAnalyzer -Path Detect.ps1 -CustomRulePath $rules -IncludeRule 'Measure-IslModuleDependency'

        The IslModuleDependency findings for Detect.ps1, as DiagnosticRecord objects.

    .INPUTS
        None.

    .OUTPUTS
        Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]
    #>
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
    <#
    .SYNOPSIS
        Reports the IslScriptSize findings as PSScriptAnalyzer records.

    .DESCRIPTION
        A PSScriptAnalyzer custom rule for IntuneScriptLab's IslScriptSize. Its rule,
        Find-IslScriptSize, flags scripts over the documented 200 KB and over the size the service
        refuses. Get-IslAnalysis analyzes each file once, and Get-IslRuleRecord turns its findings
        of this rule into diagnostic records; only the root script block gives records.

    .PARAMETER ScriptBlockAst
        The script block PSScriptAnalyzer passes, once for each block of a file.

    .EXAMPLE
        $rules = Get-IntuneAnalyzerRulePath
        Invoke-ScriptAnalyzer -Path Detect.ps1 -CustomRulePath $rules -IncludeRule 'Measure-IslScriptSize'

        The IslScriptSize findings for Detect.ps1, as DiagnosticRecord objects.

    .INPUTS
        None.

    .OUTPUTS
        Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]
    #>
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
