function Find-IslPowerShell7Syntax {
    <#
    .SYNOPSIS
        Flags syntax, cmdlets, parameters and parameter values that only exist in PowerShell 7.

    .DESCRIPTION
        The Intune Management Extension runs every script with Windows PowerShell 5.1
        (observed: PSVersion 5.1.26100, Desktop edition, for remediations, platform scripts and
        Win32 detection). PowerShell 7 syntax is a parse error there, which means the script never
        runs: a detection script exits 1 and triggers the remediation, a Win32 detection reports
        "not detected". A #Requires -Version 7 ends the same way, before the first line. A cmdlet,
        a parameter or a parameter value only PowerShell 7 has does parse, so the script starts:
        that one call fails with an error and the script carries on to its own exit, without the
        result it was written to use.

    .PARAMETER Context
        The IntuneScriptLab.ScriptContext from Get-IslScriptContext: AST, tokens, bytes and the
        effective ScriptType, Context and Architecture.

    .EXAMPLE
        Find-IslPowerShell7Syntax -Context (Get-IslScriptContext -Path .\Detect.ps1)

        The findings this rule produces for one script, as IntuneScriptLab.Finding objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $rule = 'IslPowerShell7Syntax'
    $evidence = ('Scripts run under Windows PowerShell 5.1; a parse error made the detection exit 1 and run the ' +
        'remediation (REM-PS7-SYNTAX)')
    $requiresEvidence = ('#Requires -Version 7.0 under the agent: the detection exited 1 without running ' +
        '(ScriptRequiresUnmatchedPSVersion), the remediation ran and the status was Recurred (REM-PS7-REQUIRES)')
    $runtimeEvidence = ('Test-Json, ConvertFrom-Json -AsHashtable and ForEach-Object -Parallel each wrote an ' +
        'error under the agent and the detection ran on to its exit 0: "without issues", the error text in ' +
        'the error field, no remediation (REM-PS7-CMDLET, REM-PS7-PARAM, REM-PS7-PARALLEL)')
    $valueEvidence = ('Out-File -Encoding utf8NoBOM failed validation against the 5.1 set (unknown, string, ' +
        'unicode, bigendianunicode, utf8, utf7, utf32, ascii, default, oem) under the agent; no file was ' +
        'written and the detection ran on to its exit 0 (REM-PS7-ENCODING)')
    $ast = $Context.Ast

    foreach ($parseError in $Context.ParseErrors) {
        # A module the parser could not find (using module) is a dependency, not PowerShell 7 syntax
        if ("$($parseError.ErrorId)" -eq 'ModuleNotFoundDuringParse') { continue }
        $findingSplat = @{
            RuleName = $rule
            Severity = 'Error'
            Context  = $Context
            Extent   = $parseError.Extent
            Message  = "Parse error: $($parseError.Message)"
            Evidence = $evidence
        }
        New-IslFinding @findingSplat
    }

    $requires = $ast.ScriptRequirements
    if ($requires -and $requires.RequiredPSVersion -and $requires.RequiredPSVersion.Major -ge 6) {
        $findingSplat = @{
            RuleName = $rule
            Severity = 'Error'
            Context  = $Context
            Extent   = $ast.Extent
            Message  = ("'#Requires -Version $($requires.RequiredPSVersion)' cannot be satisfied: Intune runs " +
                'Windows PowerShell 5.1, so the script exits 1 before its first line')
            Evidence = $requiresEvidence
        }
        New-IslFinding @findingSplat
    }

    $syntaxNodes = Find-IslAstNode -Ast $ast -TypeName TernaryExpressionAst, PipelineChainAst
    foreach ($node in $syntaxNodes) {
        $what = if ($node.GetType().Name -eq 'TernaryExpressionAst') { 'Ternary operator (? :)' }
        else { 'Pipeline chain operator (&& / ||)' }
        $findingSplat = @{
            RuleName = $rule
            Severity = 'Error'
            Context  = $Context
            Extent   = $node.Extent
            Message  = "$what is PowerShell 7 only; Windows PowerShell 5.1 fails to parse the whole script"
            Evidence = $evidence
        }
        New-IslFinding @findingSplat
    }

    $coalesce = Find-IslAstNode -Ast $ast -TypeName BinaryExpressionAst, AssignmentStatementAst -Where {
        param($node) "$($node.Operator)" -in 'QuestionQuestion', 'QuestionQuestionEquals'
    }
    foreach ($node in $coalesce) {
        $findingSplat = @{
            RuleName = $rule
            Severity = 'Error'
            Context  = $Context
            Extent   = $node.Extent
            Message  = ('Null-coalescing operator (?? / ??=) is PowerShell 7 only; Windows PowerShell 5.1 ' +
                'fails to parse the whole script')
            Evidence = $evidence
        }
        New-IslFinding @findingSplat
    }

    $memberTypes = 'MemberExpressionAst', 'InvokeMemberExpressionAst', 'IndexExpressionAst'
    $nullConditional = Find-IslAstNode -Ast $ast -TypeName $memberTypes -Where {
        param($node)
        $property = $node.PSObject.Properties['NullConditional']
        $property -and $property.Value
    }
    foreach ($node in $nullConditional) {
        $findingSplat = @{
            RuleName = $rule
            Severity = 'Error'
            Context  = $Context
            Extent   = $node.Extent
            Message  = ('Null-conditional member access (?. / ?[]) is PowerShell 7 only; Windows PowerShell ' +
                '5.1 fails to parse the whole script')
            Evidence = $evidence
        }
        New-IslFinding @findingSplat
    }

    # From here on the script parses, so it starts: the call fails where it stands and the script
    # carries on to its own exit, which is the opposite of what a parse error does to a detection
    foreach ($command in (Find-IslCommand -Ast $ast -Name 'ForEach-Object', '%', 'foreach')) {
        if (Test-IslCommandParameter -Command $command -ParameterName 'Parallel') {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Error'
                Context  = $Context
                Extent   = $command.Extent
                Message  = ('ForEach-Object -Parallel is PowerShell 7 only: under Windows PowerShell 5.1 the ' +
                    'call fails with an error and the script carries on without its result')
                Evidence = $runtimeEvidence
            }
            New-IslFinding @findingSplat
        }
    }

    $coreOnlyCommands = 'Get-Error', 'Join-String', 'Test-Json', 'ConvertFrom-Markdown', 'Get-Uptime',
    'Remove-Alias', 'Get-ExperimentalFeature', 'Get-MarkdownOption', 'Show-Markdown', 'Switch-Process',
    'ConvertTo-CliXml', 'ConvertFrom-CliXml'
    foreach ($command in (Find-IslCommand -Ast $ast -Name $coreOnlyCommands)) {
        $findingSplat = @{
            RuleName = $rule
            Severity = 'Error'
            Context  = $Context
            Extent   = $command.Extent
            Message  = ("$($command.GetCommandName()) does not exist in Windows PowerShell 5.1: the call " +
                'fails with an error and the script carries on without its result')
            Evidence = $runtimeEvidence
        }
        New-IslFinding @findingSplat
    }

    $coreOnlyParameters = @{
        'ConvertFrom-Json'   = 'AsHashtable', 'Depth', 'NoEnumerate', 'DateKind'
        'ConvertTo-Json'     = 'AsArray', 'EnumsAsStrings', 'EscapeHandling'
        'Split-Path'         = 'LeafBase', 'Extension'
        'Get-ChildItem'      = 'FollowSymlink'
        'Invoke-WebRequest'  = 'SkipCertificateCheck', 'SkipHttpErrorCheck', 'Form', 'Resume',
            'StatusCodeVariable', 'Authentication', 'Token', 'AllowInsecureRedirect', 'RetryIntervalSec'
        'Invoke-RestMethod'  = 'SkipCertificateCheck', 'SkipHttpErrorCheck', 'Form', 'Resume',
            'StatusCodeVariable', 'Authentication', 'Token', 'AllowInsecureRedirect', 'ResponseHeadersVariable'
        'Select-String'      = 'Raw', 'Culture', 'NoEmphasis'
        'Test-Connection'    = 'TargetName', 'TcpPort', 'Ping', 'Traceroute', 'IPv4', 'IPv6', 'Repeat'
        'Get-Content'        = 'AsByteStream'
        'Set-Content'        = 'AsByteStream'
        'Add-Content'        = 'AsByteStream'
        'Start-Process'      = 'Environment'

        'Compress-Archive'   = 'PassThru'
        'Import-Module'      = 'UseWindowsPowerShell', 'SkipEditionCheck'
    }
    foreach ($commandName in $coreOnlyParameters.Keys) {
        foreach ($command in (Find-IslCommand -Ast $ast -Name $commandName)) {
            foreach ($parameter in $coreOnlyParameters[$commandName]) {
                if (Test-IslCommandParameter -Command $command -ParameterName $parameter) {
                    $findingSplat = @{
                        RuleName = $rule
                        Severity = 'Error'
                        Context  = $Context
                        Extent   = $command.Extent
                        Message  = ("$commandName -$parameter does not exist in Windows PowerShell 5.1: the " +
                            'call fails with an error and the script carries on without its result')
                        Evidence = $runtimeEvidence
                    }
                    New-IslFinding @findingSplat
                }
            }
        }
    }

    # A parameter both hosts have, with a value only PowerShell 7 accepts
    $coreOnlyValues = @{
        'Out-File' = @{ Encoding = 'utf8NoBOM' }
    }
    foreach ($commandName in $coreOnlyValues.Keys) {
        foreach ($command in (Find-IslCommand -Ast $ast -Name $commandName)) {
            foreach ($parameter in $coreOnlyValues[$commandName].Keys) {
                $elements = @($command.CommandElements)
                $argument = $null
                for ($index = 1; $index -lt $elements.Count -and -not $argument; $index++) {
                    $element = $elements[$index]
                    if ($element.GetType().Name -ne 'CommandParameterAst') { continue }
                    if (-not $parameter.StartsWith($element.ParameterName, 'OrdinalIgnoreCase')) { continue }
                    $argument = if ($element.Argument) { $element.Argument }
                    elseif ($index + 1 -lt $elements.Count) { $elements[$index + 1] }
                }
                $isLiteral = $argument -and $argument.GetType().Name -eq 'StringConstantExpressionAst'
                if ($isLiteral -and $argument.Value -in $coreOnlyValues[$commandName][$parameter]) {
                    $findingSplat = @{
                        RuleName = $rule
                        Severity = 'Error'
                        Context  = $Context
                        Extent   = $command.Extent
                        Message  = ("$commandName -$parameter $($argument.Value) is a PowerShell 7 value: " +
                            'under Windows PowerShell 5.1 the call fails with an error, writes nothing, and ' +
                            'the script carries on')
                        Evidence = $valueEvidence
                    }
                    New-IslFinding @findingSplat
                }
            }
        }
    }
}
