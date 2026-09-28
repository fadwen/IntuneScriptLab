function Test-IntuneAssignmentFilter {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Evaluates an assignment filter rule against a device the way the Intune service does.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.FilterResult')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$Rule,

        [Parameter(Position = 1)]
        $Device,

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
        elseif (-not $SyntaxOnly) { $source = Get-IslFilterDeviceFact }
        if ($source -is [System.Collections.IDictionary]) {
            foreach ($key in $source.Keys) { $facts["$key"] = $source[$key] }
        }
        elseif ($null -ne $source) {
            foreach ($property in $source.PSObject.Properties) { $facts[$property.Name] = $property.Value }
        }
        $view = [ordered]@{}
        foreach ($key in @($facts.Keys | Sort-Object)) { $view[$key] = $facts[$key] }
        $deviceView = [pscustomobject]$view

        function Get-VersionPart {
            # Four numeric parts, missing ones as 0; $null when the text is not a version
            param([string]$Text)
            if ($Text -notmatch '^\s*\d+(\.\d+){0,3}\s*$') { return $null }
            $parts = [System.Collections.Generic.List[long]]::new()
            foreach ($part in ($Text.Trim() -split '\.')) { $parts.Add([long]$part) }
            while ($parts.Count -lt 4) { $parts.Add(0) }
            $parts.ToArray()
        }

        function Compare-Version {
            # -1, 0 or 1 the way the filter evaluator ordered versions; $null when a side is not one
            param([string]$Actual, [string]$Expected)
            $left = Get-VersionPart -Text $Actual
            $right = Get-VersionPart -Text $Expected
            if ($null -eq $left -or $null -eq $right) { return $null }
            for ($index = 0; $index -lt 4; $index++) {
                if ($left[$index] -lt $right[$index]) { return -1 }
                if ($left[$index] -gt $right[$index]) { return 1 }
            }
            0
        }

        function Test-Clause {
            param($Clause)
            $raw = if ($facts.ContainsKey($Clause.Property)) { $facts[$Clause.Property] } else { $null }
            $actual = if ($null -eq $raw) { '' } else { "$raw" }
            $Clause.Actual = if ($null -eq $raw) { $null } else { "$raw" }
            $values = @(foreach ($item in @($Clause.Value)) { if ($null -ne $item) { "$item".Trim() } })
            $expected = if ($values.Count) { $values[0] } else { '' }
            $ignoreCase = [System.StringComparison]::OrdinalIgnoreCase
            $order = $null
            if ($Clause.Kind -eq 'Version') { $order = Compare-Version -Actual $actual -Expected $expected }
            $matched = switch ($Clause.Operator) {
                'eq' { if ($Clause.Kind -eq 'Version') { $order -eq 0 } else { $actual -eq $expected } }
                'ne' { if ($Clause.Kind -eq 'Version') { $order -ne 0 } else { $actual -ne $expected } }
                'in' { $values -contains $actual }
                'notIn' { $values -notcontains $actual }
                'startsWith' { $actual.StartsWith($expected, $ignoreCase) }
                'contains' { $actual.IndexOf($expected, $ignoreCase) -ge 0 }
                'notContains' { $actual.IndexOf($expected, $ignoreCase) -lt 0 }
                'gt' { $null -ne $order -and $order -gt 0 }
                'ge' { $null -ne $order -and $order -ge 0 }
                'lt' { $null -ne $order -and $order -lt 0 }
                'le' { $null -ne $order -and $order -le 0 }
            }
            $Clause.Matched = [bool]$matched
            $Clause.Matched
        }

        function Test-Node {
            param($Node)
            switch ($Node.Type) {
                'Clause' { Test-Clause -Clause $Node.Clause }
                'And' {
                    # Both sides run so every clause reports what it saw
                    $left = Test-Node -Node $Node.Left
                    $right = Test-Node -Node $Node.Right
                    $left -and $right
                }
                'Or' {
                    $left = Test-Node -Node $Node.Left
                    $right = Test-Node -Node $Node.Right
                    $left -or $right
                }
            }
        }
    }

    process {
        $parsed = ConvertFrom-IslFilterRule -Rule $Rule
        if ($parsed.Error) {
            $errorSplat = @{
                Message      = $parsed.Error
                ErrorId      = 'IslFilterRuleInvalid'
                Category     = 'InvalidData'
                TargetObject = $Rule
            }
            Write-Error @errorSplat
            return
        }
        foreach ($warning in $parsed.Warnings) { Write-Warning $warning.Message }

        $matched = $null
        $applicable = $null
        $clauseCount = @($parsed.Clauses).Count
        if ($SyntaxOnly) {
            $reason = "The rule is valid: $clauseCount clause(s), $(@($parsed.Warnings).Count) warning(s)"
        }
        else {
            $matched = [bool](Test-Node -Node $parsed.Tree)
            $applicable = if ($Mode -eq 'Include') { $matched } else { -not $matched }
            $reason = if ($Mode -eq 'Include' -and $matched) {
                'Included: the rule matches this device, so the assignment applies'
            }
            elseif ($Mode -eq 'Include') {
                'Not applicable: the rule does not match this device; the portal shows "Filters criteria ' +
                'are not met." (W32-FILTER-INCLUDE)'
            }
            elseif ($matched) {
                'Not applicable: the exclude rule matches this device (W32-FILTER-EXCLUDE)'
            }
            else {
                'Included: the exclude rule does not match this device, so the assignment applies'
            }
        }
        Write-Verbose "Rule with $clauseCount clause(s): matched=$matched applicable=$applicable"
        [pscustomobject]@{
            PSTypeName = 'IntuneScriptLab.FilterResult'
            Rule       = $Rule
            Mode       = $Mode
            Matched    = $matched
            Applicable = $applicable
            Reason     = $reason
            Clauses    = $parsed.Clauses
            Warnings   = @($parsed.Warnings | ForEach-Object { $_.Message })
            Device     = $deviceView
        }
    }

    end {
        Write-Verbose "Completed $($MyInvocation.MyCommand.Name)"
    }
}
