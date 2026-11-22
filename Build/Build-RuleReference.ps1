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

    .PARAMETER ModuleRoot
        The repository root, which is the module root. Defaults to the parent of the folder that
        holds this script.

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
[OutputType([string])]
param(
    [Parameter()]
    [switch]$PassThru,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ModuleRoot = (Split-Path -Path $PSScriptRoot -Parent)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$privateFolder = Join-Path -Path $ModuleRoot -ChildPath 'Private'
$rulesFolder = Join-Path -Path $privateFolder -ChildPath 'Rules'
$docsFolder = Join-Path -Path $ModuleRoot -ChildPath 'docs'
$outputPath = Join-Path -Path $docsFolder -ChildPath 'Rules.md'


function Resolve-Text {
    <#
    .SYNOPSIS
    Folds a string expression of a rule file to the text it produces.

    .DESCRIPTION
    Resolves string constants, expandable strings, "+" concatenations, parentheses, and variables
    assigned earlier in the same file. A value that is only known when the rule runs becomes a
    placeholder, and an expression of any other kind is returned as its source text, so nothing
    is dropped. A literal $ is marked with the character U+0001 so that ConvertTo-Placeholder
    leaves it alone.

    .PARAMETER Ast
    The expression to resolve.

    .PARAMETER Assignments
    Every assignment to a variable in the rule file, in which the value of a variable is looked
    up.

    .EXAMPLE
    Resolve-Text -Ast $pair.Item2 -Assignments $assignments

    Resolves the value of one key of a finding hashtable.

    .INPUTS
    None.

    .OUTPUTS
    System.String. The resolved text.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [System.Management.Automation.Language.Ast]$Ast,

        [Parameter()]
        [object[]]$Assignments
    )

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
            # An assignment in parentheses has no pipeline elements to read
            if ($Ast.Pipeline.PSObject.Properties['PipelineElements']) {
                $inner = $Ast.Pipeline.PipelineElements[0]
                if ($inner.PSObject.Properties['Expression']) {
                    return Resolve-Text -Ast $inner.Expression -Assignments $Assignments
                }
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
            } elseif ($right -is [System.Management.Automation.Language.SwitchStatementAst]) {
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


function Resolve-Body {
    <#
    .SYNOPSIS
    Resolves the text that one branch of an if or switch statement yields.

    .DESCRIPTION
    A statement block that holds one string expression is resolved with Resolve-Text. For any
    other block, the string constants in it are joined with spaces.

    .PARAMETER Body
    The statement block of the branch.

    .PARAMETER Assignments
    Every assignment to a variable in the rule file, passed on to Resolve-Text.

    .EXAMPLE
    Resolve-Body -Body $ifStatement.ElseClause -Assignments $assignments

    Resolves the text of an else branch.

    .INPUTS
    None.

    .OUTPUTS
    System.String. The resolved text.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.StatementBlockAst]$Body,

        [Parameter()]
        [object[]]$Assignments
    )

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


function ConvertTo-Placeholder {
    <#
    .SYNOPSIS
    Replaces the run-time values in a resolved message with the placeholder <value>.

    .DESCRIPTION
    A subexpression, a variable in braces, and a plain variable each become <value>. The
    character U+0001, which Resolve-Text writes for a literal $, becomes $ again, and runs of
    white space become one space.

    .PARAMETER Text
    The text that Resolve-Text returned.

    .EXAMPLE
    ConvertTo-Placeholder -Text 'Found $($items.Count) items in $path'

    Returns 'Found <value> items in <value>'.

    .INPUTS
    None.

    .OUTPUTS
    System.String. The text with placeholders.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string]$Text
    )

    $resolved = [regex]::Replace($Text, '\$\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\)', '<value>')
    $resolved = [regex]::Replace($resolved, '\$\{[^}]+\}', '<value>')
    $resolved = [regex]::Replace($resolved, '\$[A-Za-z_][\w:]*', '<value>')
    $resolved = $resolved.Replace([string][char]1, '$')
    ($resolved -replace '\s+', ' ').Trim()
}


function ConvertTo-Cell {
    <#
    .SYNOPSIS
    Converts a resolved message to the text of one Markdown table cell.

    .DESCRIPTION
    Replaces run-time values with placeholders, as ConvertTo-Placeholder does, and escapes each
    vertical bar so that it does not end the cell.

    .PARAMETER Text
    The text that Resolve-Text returned.

    .EXAMPLE
    ConvertTo-Cell -Text 'exit 0 | exit 1'

    Returns 'exit 0 \| exit 1'.

    .INPUTS
    None.

    .OUTPUTS
    System.String. The cell text.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string]$Text
    )

    (ConvertTo-Placeholder -Text $Text) -replace '\|', '\|'
}


function Get-HelpText {
    <#
    .SYNOPSIS
    Gets the text of one keyword from the comment-based help in a rule file.

    .DESCRIPTION
    Reads the lines under the keyword up to the next keyword or the end of the help block, and
    joins them into one line. The file is read as text and is not loaded, so the rule does not
    run.

    .PARAMETER Source
    The whole text of the rule file.

    .PARAMETER Keyword
    The help keyword without its dot, such as SYNOPSIS or DESCRIPTION.

    .EXAMPLE
    Get-HelpText -Source $source -Keyword 'SYNOPSIS'

    Returns the synopsis of the rule as one line, or an empty string when there is none.

    .INPUTS
    None.

    .OUTPUTS
    System.String. The help text on one line.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Keyword
    )

    $match = [regex]::Match($Source, "(?s)\.$Keyword\s*\r?\n(.*?)(?=\r?\n\s*\.[A-Z]+|\r?\n\s*#>)")
    if (-not $match.Success) { return '' }
    $helpLines = $match.Groups[1].Value -split '\r?\n' | ForEach-Object { $_.Trim() }
    (($helpLines -join ' ') -replace '\s+', ' ').Trim()
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
foreach ($file in (Get-ChildItem -LiteralPath $rulesFolder -Filter 'Find-Isl*.ps1' | Sort-Object -Property Name)) {
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
$null = New-Item -ItemType Directory -Path $docsFolder -Force
[System.IO.File]::WriteAllText($outputPath, $markdown, [System.Text.UTF8Encoding]::new($false))
Write-Information -InformationAction Continue -MessageData "Rule reference written: $outputPath"
