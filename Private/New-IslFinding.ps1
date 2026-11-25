function New-IslFinding {
    <#
    .SYNOPSIS
        Builds one analysis finding.

    .DESCRIPTION
        Every rule reports through this so the output shape is uniform: rule name, severity,
        message, where in the script, and the observed Intune behaviour that justifies it
        (a short evidence string, mirrored in Validation\Findings.md).

    .PARAMETER RuleName
        The rule that found it, such as IslLongSleep.

    .PARAMETER Severity
        Error, Warning or Information.

    .PARAMETER Message
        What is wrong and what happens on a device.

    .PARAMETER Extent
        The script element the finding is about, which gives its line, column and text. Leave
        it out for a finding about the whole script.

    .PARAMETER Context
        The IntuneScriptLab.ScriptContext of the script, from Get-IslScriptContext.

    .PARAMETER Evidence
        What Intune was observed to do that makes this a problem, ending in its experiment ids.

    .PARAMETER Fix
        An edit Repair-IntuneScript can apply without changing behaviour: @{ Replacement = '...' }
        for the extent, or @{ Encoding = 'UTF8BOM' } for the file.

    .EXAMPLE
        New-IslFinding -RuleName 'IslLongSleep' -Severity 'Warning' -Message $message -Context $Context

        One IntuneScriptLab.Finding about the whole script.

    .INPUTS
        None.

    .OUTPUTS
        IntuneScriptLab.Finding.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.Finding')]
    # Builds an object; nothing outside the pipeline changes
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param(
        [Parameter(Mandatory)]
        [string]$RuleName,

        [Parameter(Mandatory)]
        [ValidateSet('Error', 'Warning', 'Information')]
        [string]$Severity,

        [Parameter(Mandatory)]
        [string]$Message,

        # The script element the finding is about; supplies file, line, column and text
        [System.Management.Automation.Language.IScriptExtent]$Extent,

        [Parameter(Mandatory)]
        [pscustomobject]$Context,

        # What Intune was observed to do that makes this a problem
        [string]$Evidence,

        # A mechanical, behaviour-preserving edit Repair-IntuneScript can apply: @{ Replacement = '...' }
        # for the extent, or @{ Encoding = 'UTF8BOM' } for the file
        [hashtable]$Fix
    )

    [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.Finding'
        RuleName = $RuleName
        Severity = $Severity
        Message = $Message
        ScriptPath = $Context.Path
        Line = if ($Extent) { $Extent.StartLineNumber } else { 0 }
        Column = if ($Extent) { $Extent.StartColumnNumber } else { 0 }
        ScriptType = $Context.ScriptType
        Text = if ($Extent) { $Extent.Text } else { '' }
        Evidence = $Evidence
        Suppressed = $false
        Fix = $Fix
    }
}
