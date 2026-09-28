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
        function Get-RelativeUri {
            param([string]$FilePath)
            $relative = if ($FilePath.StartsWith($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                $FilePath.Substring($rootPath.Length).TrimStart('\', '/')
            }
            else { $FilePath }
            $segments = $relative -split '[\\/]' | ForEach-Object { [System.Uri]::EscapeDataString($_) }
            $segments -join '/'
        }

        $ruleIndex = [ordered]@{}
        $rules = [System.Collections.Generic.List[object]]::new()
        foreach ($name in @($all | ForEach-Object { $_.RuleName } | Sort-Object -Unique)) {
            $summary = ''
            $description = ''
            $level = 'warning'
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
                            artifactLocation = [ordered]@{
                                uri       = Get-RelativeUri -FilePath "$($item.ScriptPath)"
                                uriBaseId = '%SRCROOT%'
                            }
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

        $folder = Split-Path -Path $Path -Parent
        if ($folder) { $null = New-Item -ItemType Directory -Path $folder -Force }
        $json = $log | ConvertTo-Json -Depth 12
        [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
        Write-Verbose "Wrote $($all.Count) result(s) for $($rules.Count) rule(s) to $Path"
        Get-Item -LiteralPath $Path
    }
}
