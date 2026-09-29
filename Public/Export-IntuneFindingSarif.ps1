function Export-IntuneFindingSarif {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Writes IntuneScriptLab findings as a SARIF 2.1.0 log for code scanning.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyCollection()]
        [pscustomobject[]]$Finding,

        [Parameter(Mandatory)]
        [string]$Path,

        [string]$Root = $(if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path })
    )

    begin {
        $all = [System.Collections.Generic.List[object]]::new()
        $levels = @{ Error = 'error'; Warning = 'warning'; Information = 'note' }
        $module = $MyInvocation.MyCommand.Module
        $rootPath = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).ProviderPath.TrimEnd('\', '/')
        # The context note and the pre-flight's policy checks have no rule function to read help from
        $fixedRules = @{
            IslAssumedContext     = @{
                Level   = 'note'
                Summary = 'The script type, context and architecture were assumed, not declared.'
            }
            IslDetectionRuleIssue = @{
                Level   = 'error'
                Summary = 'A Win32 detection rule the agent does not evaluate.'
            }
            IslAssignmentIssue    = @{
                Level   = 'warning'
                Summary = 'A Win32 app assignment that can never install.'
            }
            IslDetectOnly         = @{
                Level   = 'note'
                Summary = 'A remediation with no remediation script runs its detection alone.'
            }
        }
    }

    process {
        foreach ($item in $Finding) { if ($null -ne $item) { $all.Add($item) } }
    }

    end {
        function Get-ArtifactLocation {
            param([string]$FilePath)
            if ($FilePath.StartsWith($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                $relative = $FilePath.Substring($rootPath.Length).TrimStart('\', '/')
                $segments = $relative -split '[\\/]' | ForEach-Object { [System.Uri]::EscapeDataString($_) }
                return [ordered]@{ uri = ($segments -join '/'); uriBaseId = '%SRCROOT%' }
            }
            # Outside the root: an absolute file URI, with no base to resolve against
            [ordered]@{ uri = ([System.Uri]::new($FilePath)).AbsoluteUri }
        }

        $ruleIndex = [ordered]@{}
        $rules = [System.Collections.Generic.List[object]]::new()
        foreach ($name in @($all | ForEach-Object { $_.RuleName } | Sort-Object -Unique)) {
            $summary = ''
            $description = ''
            # The level of the most severe finding the rule produced in this log; the fixed-table
            # rules carry their own
            $rank = @{ note = 0; warning = 1; error = 2 }
            $level = 'note'
            foreach ($item in ($all | Where-Object RuleName -eq $name)) {
                $itemLevel = $levels["$($item.Severity)"]
                if ($itemLevel -and $rank[$itemLevel] -gt $rank[$level]) { $level = $itemLevel }
            }
            if ($fixedRules.ContainsKey($name)) {
                $summary = $fixedRules[$name].Summary
                $level = $fixedRules[$name].Level
            }
            elseif (Get-Command -Name "Find-$name" -ErrorAction SilentlyContinue) {
                $help = Get-Help -Name "Find-$name" -ErrorAction SilentlyContinue
                $summary = "$($help.Synopsis)".Trim()
                $description = (@($help.Description | ForEach-Object { $_.Text }) -join ' ') -replace '\s+', ' '
            }
            if (-not $summary) { $summary = $name }
            $rule = [ordered]@{
                id               = $name
                name             = $name
                shortDescription = [ordered]@{ text = $summary }
            }
            if ($description) { $rule.fullDescription = [ordered]@{ text = $description.Trim() } }
            $rule.defaultConfiguration = [ordered]@{ level = $level }
            $ruleIndex[$name] = $rules.Count
            $rules.Add($rule)
        }

        $results = foreach ($item in $all) {
            $region = [ordered]@{ startLine = [Math]::Max(1, [int]$item.Line) }
            if ($item.Column -gt 0) { $region.startColumn = [int]$item.Column }
            if ($item.Text) { $region.snippet = [ordered]@{ text = "$($item.Text)" } }
            $result = [ordered]@{
                ruleId    = $item.RuleName
                ruleIndex = $ruleIndex[$item.RuleName]
                level     = $levels["$($item.Severity)"]
                message   = [ordered]@{ text = "$($item.Message)" }
                locations = @(
                    [ordered]@{
                        physicalLocation = [ordered]@{
                            artifactLocation = Get-ArtifactLocation -FilePath "$($item.ScriptPath)"
                            region           = $region
                        }
                    }
                )
                properties = [ordered]@{
                    scriptType = "$($item.ScriptType)"
                    evidence   = "$($item.Evidence)"
                }
            }
            if ($item.PSObject.Properties['Suppressed'] -and $item.Suppressed) {
                $result.suppressions = @([ordered]@{ kind = 'inSource' })
            }
            $result
        }

        $rootUri = ([System.Uri]::new($rootPath + [System.IO.Path]::DirectorySeparatorChar)).AbsoluteUri
        $driver = [ordered]@{
            name           = 'IntuneScriptLab'
            version        = "$($module.Version)"
            informationUri = "$($module.PrivateData.PSData.ProjectUri)"
            rules          = @($rules)
        }
        $log = [ordered]@{
            '$schema' = 'https://json.schemastore.org/sarif-2.1.0.json'
            version   = '2.1.0'
            runs      = @(
                [ordered]@{
                    tool               = [ordered]@{ driver = $driver }
                    originalUriBaseIds = [ordered]@{ '%SRCROOT%' = [ordered]@{ uri = $rootUri } }
                    results            = @($results)
                }
            )
        }

        # Resolved against the PowerShell location: .NET's current directory is not $PWD
        $outFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        $folder = Split-Path -Path $outFile -Parent
        if ($folder) { $null = New-Item -ItemType Directory -Path $folder -Force }
        $json = $log | ConvertTo-Json -Depth 12
        [System.IO.File]::WriteAllText($outFile, $json, [System.Text.UTF8Encoding]::new($false))
        Write-Verbose "Wrote $($all.Count) result(s) for $($rules.Count) rule(s) to $outFile"
        Get-Item -LiteralPath $outFile
    }
}
