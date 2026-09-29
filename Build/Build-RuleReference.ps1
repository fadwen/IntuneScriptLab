#Requires -Version 5.1

<#
    .SYNOPSIS
        Generates docs\Rules.md, every finding each rule can produce with the observation behind it.

    .DESCRIPTION
        Reads the rule files under Private\Rules without running them: each rule's synopsis and
        description come from its comment help, and each finding it can produce comes from the
        hashtable it hands to New-IslFinding, with the Severity, the Message and the Evidence
        resolved from the string constants, concatenations and variables of the file. Text a rule
        fills in at run time (a command name, a count, a path) appears as <value>.

        The result is the rule reference: one section per rule with a table of severity, message
        and evidence, and the experiment ids the evidence cites (the names in
        Validation\Experiments.psd1, the rows of Validation\Findings.md). The unit test
        RuleReference.Tests.ps1 fails when the committed file no longer matches the rules, so run this
        after changing a rule.

    .PARAMETER PassThru
        Return the Markdown as a string instead of writing docs\Rules.md.

    .EXAMPLE
        .\Build\Build-RuleReference.ps1

        Rewrites docs\Rules.md from the current rules.

    .EXAMPLE
        .\Build\Build-RuleReference.ps1 -PassThru | Select-String '^## '

        The rules the reference would document, without writing it.

    .EXAMPLE
        .\Build\Build-RuleReference.ps1; git diff --stat docs\Rules.md

        Regenerates the reference and shows whether a rule change altered it.

    .INPUTS
        None.

    .OUTPUTS
        System.String with -PassThru; otherwise none, the file is written.

    .NOTES
        Author: Jeffrey Stuhr. A finding whose message or evidence the parser cannot resolve is shown
        as its source text, so nothing is silently dropped.
#>
[CmdletBinding()]
param(
    [switch]$PassThru,

    # Repository root, the module root; the parent of the folder holding this script
    [ValidateNotNullOrEmpty()]
    [string]$ModuleRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$moduleRoot = $ModuleRoot
$rulesFolder = Join-Path -Path $moduleRoot -ChildPath 'Private\Rules'
$outputPath = Join-Path -Path $moduleRoot -ChildPath 'docs\Rules.md'

# A string expression folded to text: constants, expandable strings, "+" concatenations,
# parentheses and variables assigned earlier in the same file
function Resolve-Text {
    param($Ast, [object[]]$Assignments)
    if ($null -eq $Ast) { return '' }
    switch ($Ast.GetType().Name) {
        # A literal $ (single-quoted, or escaped in a double-quoted string) is text, not a value:
        # marked so the placeholder pass leaves it alone
        'StringConstantExpressionAst' { return $Ast.Value.Replace('$', [string][char]1) }
        'ExpandableStringExpressionAst' {
            $text = $Ast.Value
            foreach ($nested in ($Ast.NestedExpressions | Sort-Object { $_.Extent.StartOffset } -Descending)) {
                $index = $text.LastIndexOf($nested.Extent.Text)
                if ($index -ge 0) {
                    $text = $text.Substring(0, $index) + '<value>' +
                        $text.Substring($index + $nested.Extent.Text.Length)
                }
            }
            return $text.Replace('$', [string][char]1)
        }
        'ParenExpressionAst' {
            $inner = $Ast.Pipeline.PipelineElements[0]
            if ($inner.PSObject.Properties['Expression']) {
                return Resolve-Text -Ast $inner.Expression -Assignments $Assignments
            }
            return $Ast.Extent.Text
        }
        'BinaryExpressionAst' {
            if ("$($Ast.Operator)" -eq 'Plus') {
                return (Resolve-Text -Ast $Ast.Left -Assignments $Assignments) +
                (Resolve-Text -Ast $Ast.Right -Assignments $Assignments)
            }
            return $Ast.Extent.Text
        }
        'VariableExpressionAst' {
            $name = $Ast.VariablePath.UserPath
            $earlier = @($Assignments | Where-Object {
                    $_.Left.Extent.Text -eq "`$$name" -and $_.Extent.StartOffset -lt $Ast.Extent.StartOffset
                }) | Select-Object -Last 1
            if (-not $earlier) { return "<$name>" }
            $right = $earlier.Right
            if ($right -is [System.Management.Automation.Language.CommandExpressionAst]) {
                return Resolve-Text -Ast $right.Expression -Assignments $Assignments
            }
            if ($right -is [System.Management.Automation.Language.PipelineAst]) {
                $first = $right.PipelineElements[0]
                if ($first.PSObject.Properties['Expression']) {
                    return Resolve-Text -Ast $first.Expression -Assignments $Assignments
                }
            }
            # "$severity = if (...) { 'Warning' } else { 'Information' }" and
            # "$message = switch ($type) { 'X' { '...' } default { '...' } }": each branch's text,
            # the conditions left out
            $bodies = @()
            $joiner = ' or '
            if ($right -is [System.Management.Automation.Language.IfStatementAst]) {
                $bodies = @($right.Clauses | ForEach-Object { $_.Item2 })
                if ($right.ElseClause) { $bodies += $right.ElseClause }
            }
            elseif ($right -is [System.Management.Automation.Language.SwitchStatementAst]) {
                $bodies = @($right.Clauses | ForEach-Object { $_.Item2 })
                if ($right.Default) { $bodies += $right.Default }
                $joiner = ' / '
            }
            $texts = @(foreach ($body in $bodies) { Resolve-Body -Body $body -Assignments $Assignments })
            $texts = @($texts | Where-Object { $_ } | Select-Object -Unique)
            if ($texts.Count) { return ($texts -join $joiner) }
            return "<$name>"
        }
        default { return $Ast.Extent.Text }
    }
}

# A statement block that yields one string expression, resolved; anything else, its constants
function Resolve-Body {
    param($Body, [object[]]$Assignments)
    $statements = @($Body.Statements)
    if ($statements.Count -eq 1 -and $statements[0].PSObject.Properties['PipelineElements']) {
        $first = $statements[0].PipelineElements[0]
        if ($first.PSObject.Properties['Expression']) {
            return Resolve-Text -Ast $first.Expression -Assignments $Assignments
        }
    }
    $constants = @($Body.FindAll({ param($node)
                $node -is [System.Management.Automation.Language.StringConstantExpressionAst]
            }, $true) | ForEach-Object { $_.Value })
    $constants -join ' '
}

# Run-time text in a message becomes a placeholder
function ConvertTo-Placeholder {
    param([string]$Text)
    $text = [regex]::Replace($Text, '\$\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\)', '<value>')
    $text = [regex]::Replace($text, '\$\{[^}]+\}', '<value>')
    $text = [regex]::Replace($text, '\$[A-Za-z_][\w:]*', '<value>')
    $text = $text.Replace([string][char]1, '$')
    ($text -replace '\s+', ' ').Trim()
}

function ConvertTo-Cell {
    param([string]$Text)
    (ConvertTo-Placeholder -Text $Text) -replace '\|', '\|'
}

function Get-HelpText {
    param([string]$Source, [string]$Keyword)
    $match = [regex]::Match($Source, "(?s)\.$Keyword\s*\r?\n(.*?)(?=\r?\n\s*\.[A-Z]+|\r?\n\s*#>)")
    if (-not $match.Success) { return '' }
    $lines = $match.Groups[1].Value -split "\r?\n" | ForEach-Object { $_.Trim() }
    (($lines -join ' ') -replace '\s+', ' ').Trim()
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# IntuneScriptLab rules, from the evidence')
$lines.Add('')
$lines.Add('Generated by Build\Build-RuleReference.ps1 from the rule files under Private\Rules; ' +
    'do not edit by hand.')
$lines.Add('Each row is one finding a rule can produce: its severity, its message (`<value>` stands for the')
$lines.Add('text the script itself supplies) and the observation behind it. The ids in the evidence are the')
$lines.Add('experiment names in Validation\Experiments.psd1 and the rows of Validation\Findings.md.')
$lines.Add('')

$idPattern = '\b(?:REM|PS|W32|FLT|ESP|ASSIGN|PROBE)-[A-Z0-9]+(?:-[A-Z0-9]+)*\b'
foreach ($file in (Get-ChildItem -Path $rulesFolder -Filter 'Find-Isl*.ps1' | Sort-Object Name)) {
    $source = [System.IO.File]::ReadAllText($file.FullName)
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    if ($errors) { throw "$($file.Name) does not parse: $($errors[0].Message)" }
    $assignments = @($ast.FindAll({ param($node)
                $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left -is [System.Management.Automation.Language.VariableExpressionAst]
            }, $true))
    $hashtables = @($ast.FindAll({ param($node)
                $node -is [System.Management.Automation.Language.HashtableAst] -and
                @($node.KeyValuePairs | Where-Object { $_.Item1.Extent.Text -eq 'RuleName' }).Count -and
                @($node.KeyValuePairs | Where-Object { $_.Item1.Extent.Text -eq 'Message' }).Count
            }, $true))

    $ruleName = $file.BaseName -replace '^Find-', ''
    $lines.Add("## $ruleName")
    $lines.Add('')
    $synopsis = Get-HelpText -Source $source -Keyword 'SYNOPSIS'
    $description = Get-HelpText -Source $source -Keyword 'DESCRIPTION'
    if ($synopsis) { $lines.Add($synopsis); $lines.Add('') }
    if ($description) { $lines.Add($description); $lines.Add('') }
    $lines.Add('| Severity | Message | Evidence |')
    $lines.Add('|---|---|---|')
    $ids = [System.Collections.Generic.List[string]]::new()
    foreach ($table in ($hashtables | Sort-Object { $_.Extent.StartOffset })) {
        $cells = @{}
        foreach ($pair in $table.KeyValuePairs) {
            $key = $pair.Item1.Extent.Text
            if ($key -notin 'Severity', 'Message', 'Evidence') { continue }
            $expression = $pair.Item2
            if ($expression.PSObject.Properties['PipelineElements']) {
                $expression = $expression.PipelineElements[0]
                if ($expression.PSObject.Properties['Expression']) { $expression = $expression.Expression }
            }
            $cells[$key] = Resolve-Text -Ast $expression -Assignments $assignments
        }
        $severity = if ($cells.ContainsKey('Severity')) { ConvertTo-Cell -Text $cells['Severity'] } else { '' }
        $message = if ($cells.ContainsKey('Message')) { ConvertTo-Cell -Text $cells['Message'] } else { '' }
        $evidence = if ($cells.ContainsKey('Evidence')) { ConvertTo-Cell -Text $cells['Evidence'] } else { '' }
        $lines.Add("| $severity | $message | $evidence |")
        foreach ($match in [regex]::Matches($evidence, $idPattern)) { $ids.Add($match.Value) }
    }
    $lines.Add('')
    $unique = @($ids | Sort-Object -Unique)
    if ($unique.Count) {
        $lines.Add("Experiments: $($unique -join ', ')")
        $lines.Add('')
    }
}

$markdown = ($lines -join "`n") + "`n"
if ($PassThru) { return $markdown }
$null = New-Item -ItemType Directory -Path (Split-Path -Path $outputPath -Parent) -Force
[System.IO.File]::WriteAllText($outputPath, $markdown, [System.Text.UTF8Encoding]::new($false))
Write-Information -InformationAction Continue -MessageData "Rule reference written: $outputPath"
