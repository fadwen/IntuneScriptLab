function Test-IntuneAssignmentFilter {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Evaluates an assignment filter rule against a device like the Intune service.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.FilterResult')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) })]
        [string[]]$Rule,

        [Parameter(Position = 1)]
        [object]$Device,

        [ValidateSet('Include', 'Exclude')]
        [string]$Mode = 'Include',

        [switch]$SyntaxOnly
    )

    begin {
        Write-Verbose "Starting $($MyInvocation.MyCommand.Name) ($Mode)"
        $facts = [System.Collections.Generic.Dictionary[string, object]]::new(
            [System.StringComparer]::OrdinalIgnoreCase)
        $source = $null
        if ($null -ne $Device) { $source = $Device }
        elseif (-not $SyntaxOnly) {
            # No facts, no verdict: the command ends here and process does not run
            try {
                $source = Get-IslFilterDeviceFact
            } catch {
                $PSCmdlet.ThrowTerminatingError($_)
            }
        }
        if ($source -is [System.Collections.IDictionary]) {
            foreach ($key in $source.Keys) { $facts["$key"] = $source[$key] }
        } elseif ($null -ne $source) {
            foreach ($property in $source.PSObject.Properties) { $facts[$property.Name] = $property.Value }
        }
        $view = [ordered]@{}
        foreach ($key in @($facts.Keys | Sort-Object)) { $view[$key] = $facts[$key] }
        $deviceView = [pscustomobject]$view
    }

    process {
        foreach ($ruleText in $Rule) {
            $parsed = ConvertFrom-IslFilterRule -Rule $ruleText
            if ($parsed.Error) {
                $errorSplat = @{
                    Message = $parsed.Error
                    ErrorId = 'IslFilterRuleInvalid'
                    Category = 'InvalidData'
                    TargetObject = $ruleText
                }
                # One rule that does not parse is one failed item; the rules after it are still tested
                $PSCmdlet.WriteError((New-IslErrorRecord @errorSplat))
                continue
            }
            # The parser does not know the mode; in exclude mode a clause that never matches excludes
            # nobody
            $messages = [System.Collections.Generic.List[string]]::new()
            foreach ($warning in $parsed.Warnings) {
                $messages.Add((Get-IslFilterWarningMessage -Warning $warning -Mode $Mode))
            }
            foreach ($message in $messages) { Write-Warning $message }

            $matched = $null
            $applicable = $null
            $clauseCount = @($parsed.Clauses).Count
            if ($SyntaxOnly) {
                $reason = "The rule is valid: $clauseCount clause(s), $(@($parsed.Warnings).Count) warning(s)"
            } else {
                $matched = [bool](Test-IslFilterNode -Node $parsed.Tree -Facts $facts)
                $applicable = if ($Mode -eq 'Include') { $matched } else { -not $matched }
                $reason = if ($Mode -eq 'Include' -and $matched) {
                    'Included: the rule matches this device, so the assignment applies'
                } elseif ($Mode -eq 'Include') {
                    'Not applicable: the rule does not match this device; the portal shows "Filters ' +
                    'criteria are not met." (W32-FILTER-INCLUDE)'
                } elseif ($matched) {
                    'Not applicable: the exclude rule matches this device (W32-FILTER-EXCLUDE)'
                } else {
                    'Included: the exclude rule does not match this device, so the assignment applies'
                }
            }
            Write-Verbose "Rule with $clauseCount clause(s): matched=$matched applicable=$applicable"
            [pscustomobject]@{
                PSTypeName = 'IntuneScriptLab.FilterResult'
                Rule = $ruleText
                Mode = $Mode
                Matched = $matched
                Applicable = $applicable
                Reason = $reason
                Clauses = $parsed.Clauses
                Warnings = $messages.ToArray()
                Device = $deviceView
            }
        }
    }

    end {
        Write-Verbose "Completed $($MyInvocation.MyCommand.Name)"
    }
}
