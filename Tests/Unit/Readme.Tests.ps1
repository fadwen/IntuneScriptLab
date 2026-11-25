#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The README's list of the edits Repair-IntuneScript can make, held against the rules. The list
    had drifted once (#152): it left out the -ErrorAction Stop edit and counted its edits wrong.

    The rules are read as syntax trees. A rule offers an edit where it gives a finding a Fix: a
    hashtable key Fix, or an assignment to a member or an index named Fix. Every such rule must be
    named in the list, and the list must name no other. The literal text that a Fix's Replacement
    writes, such as ' -ErrorAction Stop' or 'exit 1', must be in the list too, so that a rule with a
    second edit cannot keep only the first. An edit built from the script's own text, or from a
    table elsewhere in the rule (the switch IslInteractiveCall appends, the replacement
    Get-IslReturnReplacement builds), has no literal to compare, and is held by its rule's name only.
#>

BeforeDiscovery {
    $repositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $rulesFolder = Join-Path -Path (Join-Path -Path $repositoryRoot -ChildPath 'Private') -ChildPath 'Rules'
    $astTypes = 'System.Management.Automation.Language'

    $offering = [System.Collections.Generic.List[string]]::new()
    $texts = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($file in Get-ChildItem -LiteralPath $rulesFolder -Filter 'Find-Isl*.ps1') {
        $rule = $file.BaseName -replace '^Find-', ''
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)

        # The value of each Fix: from @{ Fix = ... }, and from $x.Fix = ... or $x['Fix'] = ...
        $fixValues = @(
            foreach ($table in $ast.FindAll({ param($node) $node -is "$astTypes.HashtableAst" }, $true)) {
                foreach ($pair in $table.KeyValuePairs) {
                    $isFixKey = $pair.Item1 -is "$astTypes.StringConstantExpressionAst" -and
                    $pair.Item1.Value -eq 'Fix'
                    if ($isFixKey) {
                        $pair.Item2
                    }
                }
            }
            $assignments = $ast.FindAll({ param($node) $node -is "$astTypes.AssignmentStatementAst" }, $true)
            foreach ($assignment in $assignments) {
                $left = $assignment.Left
                $name = if ($left -is "$astTypes.MemberExpressionAst") { "$($left.Member)" }
                elseif ($left -is "$astTypes.IndexExpressionAst") { $left.Index.SafeGetValue() }
                if ($name -eq 'Fix') {
                    $assignment.Right
                }
            }
        )
        if ($fixValues.Count -eq 0) {
            continue
        }
        $offering.Add($rule)

        # The literal text of each Replacement, leaving out an empty one (a line removed) and a
        # regular expression ('(?i)PWD', which matches the old text)
        foreach ($fixValue in $fixValues) {
            foreach ($table in $fixValue.FindAll({ param($node) $node -is "$astTypes.HashtableAst" }, $true)) {
                foreach ($pair in $table.KeyValuePairs) {
                    if ($pair.Item1.Extent.Text -ne 'Replacement') {
                        continue
                    }
                    # Quoted text only: member and command names are string constants as well
                    $constants = $pair.Item2.FindAll({
                            param($node)
                            $node -is "$astTypes.StringConstantExpressionAst" -and
                            "$($node.StringConstantType)" -ne 'BareWord'
                        }, $true)
                    foreach ($constant in $constants) {
                        $text = $constant.Value.Trim()
                        if ($text -and -not $text.StartsWith('(?')) {
                            $texts.Add(@{ Rule = $rule; Text = $text })
                        }
                    }
                }
            }
        }
    }
    $script:OfferingRules = @($offering | ForEach-Object { @{ Rule = $_ } })
    $script:ReplacementTexts = @($texts)
    $script:AllOffering = @(@{ Offering = $offering.ToArray() })
}

BeforeAll {
    $repositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $readmePath = Join-Path -Path $repositoryRoot -ChildPath 'README.md'
    $readme = [System.IO.File]::ReadAllText($readmePath).Replace("`r`n", "`n")
    $start = $readme.IndexOf('Some findings come with an edit the tool can make for you')
    $end = $readme.IndexOf('`Repair-IntuneScript` applies them', [Math]::Max($start, 0))
    $script:EditList = ''
    if ($start -ge 0 -and $end -gt $start) {
        $script:EditList = $readme.Substring($start, $end - $start)
    }
}

Describe 'The README''s list of the edits Repair-IntuneScript makes' -Tag 'Unit', 'Documentation' {

    It 'is in the README, between its opening sentence and the paragraph after it' {
        $script:EditList.Length | Should-BeGreaterThan 0
    }

    It 'lists <Rule>, which offers an edit' -ForEach $script:OfferingRules {
        $script:EditList.Contains("- ``$Rule``:") | Should-BeTrue -Because "$Rule gives a finding a Fix"
    }

    It 'names the edit ''<Text>'' of <Rule>' -ForEach $script:ReplacementTexts {
        $script:EditList.Contains($Text) | Should-BeTrue -Because "$Rule writes '$Text' as a Fix"
    }

    It 'names no rule that offers no edit' -ForEach $script:AllOffering {
        $named = @([regex]::Matches($script:EditList, '(?m)^- `(Isl\w+)`:') | ForEach-Object {
                $_.Groups[1].Value
            } | Sort-Object -Unique)

        $named.Count | Should-BeGreaterThan 0
        $Offering.Count | Should-BeGreaterThan 0
        @($named | Where-Object { $_ -notin $Offering }) | Should-BeCollection -Count 0
    }
}
