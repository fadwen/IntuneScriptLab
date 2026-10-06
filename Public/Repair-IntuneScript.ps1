function Repair-IntuneScript {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Applies the mechanical fixes for findings that have one, and reports what is left.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('IntuneScriptLab.Repair')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName', 'PSPath')]
        [SupportsWildcards()]
        [string[]]$Path,

        [ValidateSet('Auto', 'Detection', 'Remediation', 'PlatformScript', 'Win32Detection', 'Win32Requirement')]
        [string]$ScriptType = 'Auto',

        [ValidateSet('Auto', 'System', 'User')]
        [string]$Context = 'Auto',

        [ValidateSet('Auto', 'x86', 'x64', 'arm64')]
        [string]$Architecture = 'Auto',

        [string[]]$IncludeRule,

        [string[]]$ExcludeRule,

        [switch]$EnforceSignatureCheck,

        $Settings
    )

    process {
        $files = foreach ($item in $Path) {
            foreach ($resolved in (Resolve-Path -Path $item -ErrorAction Stop)) {
                if (Test-Path -LiteralPath $resolved.ProviderPath -PathType Container) {
                    Get-ChildItem -LiteralPath $resolved.ProviderPath -Recurse -Filter *.ps1 -File |
                        ForEach-Object { $_.FullName }
                }
                else { $resolved.ProviderPath }
            }
        }

        foreach ($file in $files) {
            # The analysis sees the script the way the caller deploys it, so the findings, their
            # fixes and the Remaining count are the ones Test-IntuneScript would give for the same
            # options
            $testSplat = @{
                Path = $file; ScriptType = $ScriptType; Context = $Context; Architecture = $Architecture
            }
            if ($EnforceSignatureCheck) { $testSplat.EnforceSignatureCheck = $true }
            if ($IncludeRule) { $testSplat.IncludeRule = $IncludeRule }
            if ($ExcludeRule) { $testSplat.ExcludeRule = $ExcludeRule }
            if ($PSBoundParameters.ContainsKey('Settings')) { $testSplat.Settings = $Settings }
            $findings = @(Test-IntuneScript @testSplat)
            $fixable = @($findings | Where-Object { $_.Fix })
            $fixes = [System.Collections.Generic.List[object]]::new()
            $written = $false

            if ($fixable) {
                $bytes = [System.IO.File]::ReadAllBytes($file)
                $encoding = if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
                    [System.Text.Encoding]::Unicode
                }
                elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
                    [System.Text.Encoding]::BigEndianUnicode
                }
                elseif ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and
                    $bytes[2] -eq 0xBF) {
                    [System.Text.UTF8Encoding]::new($true)
                }
                else {
                    # No BOM: UTF-8 when the bytes decode as such, otherwise the ANSI code page
                    # Windows PowerShell 5.1 reads it in (a UTF-8 decode would turn every non-ASCII
                    # character into U+FFFD and lose it for good)
                    try {
                        $null = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes)
                        [System.Text.UTF8Encoding]::new($false)
                    }
                    catch { Get-IslOemEncoding -Kind ANSI }
                }
                $text = $encoding.GetString($bytes).TrimStart([char]0xFEFF)
                $lineStarts = [System.Collections.Generic.List[int]]::new()
                $lineStarts.Add(0)
                for ($i = 0; $i -lt $text.Length; $i++) {
                    if ($text[$i] -eq "`n") { $lineStarts.Add($i + 1) }
                }

                # Text edits from the end of the file backwards, so earlier offsets stay valid
                $edits = foreach ($finding in $fixable) {
                    if (-not $finding.Fix.ContainsKey('Replacement')) { continue }
                    if ($finding.Line -lt 1 -or $finding.Line -gt $lineStarts.Count) { continue }
                    $start = $lineStarts[$finding.Line - 1] + $finding.Column - 1
                    $before = "$($finding.Text)"
                    $current = if ($start + $before.Length -le $text.Length) {
                        $text.Substring($start, $before.Length)
                    }
                    else { '' }
                    if ($current -ne $before) {
                        Write-Warning "$file line $($finding.Line): the text changed since the analysis; skipped"
                        continue
                    }
                    [pscustomobject]@{ Start = $start; Finding = $finding; Before = $before }
                }
                foreach ($edit in ($edits | Sort-Object Start -Descending)) {
                    $after = "$($edit.Finding.Fix.Replacement)"
                    $tail = $text.Substring($edit.Start + $edit.Before.Length)
                    $text = $text.Substring(0, $edit.Start) + $after + $tail
                    $fixes.Add([pscustomobject]@{
                            PSTypeName = 'IntuneScriptLab.Fix'
                            RuleName   = $edit.Finding.RuleName
                            Line       = $edit.Finding.Line
                            Before     = $edit.Before
                            After      = $after
                        })
                }
                $encodingFix = @($fixable | Where-Object { $_.Fix.ContainsKey('Encoding') }) |
                    Select-Object -First 1
                $target = $encoding
                if ($encodingFix) {
                    $target = [System.Text.UTF8Encoding]::new($true)
                    $fixes.Add([pscustomobject]@{
                            PSTypeName = 'IntuneScriptLab.Fix'
                            RuleName   = $encodingFix.RuleName
                            Line       = 0
                            Before     = $encoding.WebName
                            After      = 'utf-8 with BOM'
                        })
                }

                if ($fixes.Count -gt 0) {
                    $rules = @($fixes | ForEach-Object { $_.RuleName } | Sort-Object -Unique) -join ', '
                    if ($PSCmdlet.ShouldProcess($file, "Apply $($fixes.Count) fix(es): $rules")) {
                        [System.IO.File]::WriteAllText($file, $text, $target)
                        $written = $true
                    }
                }
            }

            $remaining = if ($written) { @(Test-IntuneScript @testSplat).Count }
            else { $findings.Count - $fixes.Count }
            [pscustomobject]@{
                PSTypeName = 'IntuneScriptLab.Repair'
                Path       = $file
                Applied    = $fixes.Count
                Remaining  = $remaining
                Written    = $written
                Fixes      = $fixes.ToArray()
            }
        }
    }
}
