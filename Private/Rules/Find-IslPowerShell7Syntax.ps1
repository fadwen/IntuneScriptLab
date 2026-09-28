function Find-IslPowerShell7Syntax {
    <#
    .SYNOPSIS
        Flags syntax, cmdlets and parameters that only exist in PowerShell 7.

    .DESCRIPTION
        The Intune Management Extension runs every script with Windows PowerShell 5.1
        (observed: PSVersion 5.1.26100, Desktop edition, for remediations, platform scripts and
        Win32 detection). A PowerShell 7-only construct is a parse error there, which means the
        script never runs: a detection script exits 1 and triggers the remediation, a Win32
        detection reports "not detected".

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
    $ast = $Context.Ast

    foreach ($parseError in $Context.ParseErrors) {
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
                'Windows PowerShell 5.1')
            Evidence = $evidence
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

    foreach ($command in (Find-IslCommand -Ast $ast -Name 'ForEach-Object', '%', 'foreach')) {
        if (Test-IslCommandParameter -Command $command -ParameterName 'Parallel') {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Error'
                Context  = $Context
                Extent   = $command.Extent
                Message  = 'ForEach-Object -Parallel is PowerShell 7 only'
                Evidence = $evidence
            }
            New-IslFinding @findingSplat
        }
    }

    # Cmdlets and parameters that do not exist in 5.1: a runtime error, not a parse error
    $coreOnlyCommands = 'Get-Error', 'Join-String', 'Test-Json', 'ConvertFrom-Markdown', 'Get-Uptime',
    'Remove-Alias', 'Get-ExperimentalFeature', 'Get-MarkdownOption', 'Show-Markdown', 'Switch-Process',
    'ConvertTo-CliXml', 'ConvertFrom-CliXml'
    foreach ($command in (Find-IslCommand -Ast $ast -Name $coreOnlyCommands)) {
        $findingSplat = @{
            RuleName = $rule
            Severity = 'Error'
            Context  = $Context
            Extent   = $command.Extent
            Message  = "$($command.GetCommandName()) does not exist in Windows PowerShell 5.1"
            Evidence = $evidence
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
        'Out-File'           = 'Encoding utf8NoBOM'
        'Start-Process'      = 'Environment'
        'Get-Process'        = 'CommandLine'
        'Compress-Archive'   = 'PassThru'
        'Import-Module'      = 'UseWindowsPowerShell', 'SkipEditionCheck'
        'New-TemporaryFile'  = 'Extension'
        'Rename-Item'        = ''
    }
    foreach ($commandName in $coreOnlyParameters.Keys) {
        foreach ($command in (Find-IslCommand -Ast $ast -Name $commandName)) {
            foreach ($parameter in ($coreOnlyParameters[$commandName] |
                Where-Object { $_ -and $_ -notmatch ' ' })) {
                if (Test-IslCommandParameter -Command $command -ParameterName $parameter) {
                    $findingSplat = @{
                        RuleName = $rule
                        Severity = 'Error'
                        Context  = $Context
                        Extent   = $command.Extent
                        Message  = "$commandName -$parameter does not exist in Windows PowerShell 5.1"
                        Evidence = $evidence
                    }
                    New-IslFinding @findingSplat
                }
            }
        }
    }
}
