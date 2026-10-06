function Find-IslInteractiveCall {
    <#
    .SYNOPSIS
        Flags anything that waits for a person.

    .DESCRIPTION
        The agent launches powershell.exe with -NoProfile -ExecutionPolicy Bypass -File and
        nothing else: no -NonInteractive. A prompt therefore doesn't fail, it waits, until the
        agent kills the script at its timeout (30 minutes for platform scripts, 60 for
        remediations and Win32 detection). Remediations run one at a time, so one hung script
        also delays every other remediation on the device.

    .PARAMETER Context
        The IntuneScriptLab.ScriptContext from Get-IslScriptContext: AST, tokens, bytes and the
        effective ScriptType, Context and Architecture.

    .EXAMPLE
        Find-IslInteractiveCall -Context (Get-IslScriptContext -Path .\Detect.ps1)

        The findings this rule produces for one script, as IntuneScriptLab.Finding objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $rule = 'IslInteractiveCall'
    $timeout = if ($Context.ScriptType -eq 'PlatformScript') { '30 minutes' } else { '60 minutes' }
    $evidence = ("Launched as powershell.exe -NoProfile -executionPolicy bypass -file, without -NonInteractive; " +
        "AgentExecutor timeout $timeout (PS-PROBE-SYS64, REM-PROBE-SYS64, Win32 log)")
    $builtEvidence = ($evidence + '; handed a PSCredential object, Get-Credential -Credential returned it ' +
        'in 12 ms under the agent, without a prompt (REM-CRED-BUILT)')
    $ast = $Context.Ast

    # What Get-Credential is handed as -Credential, by name or as the first positional argument.
    # Nothing when it is called bare or with -Message, -UserName or -Title, which always prompt
    function Get-CredentialArgument {
        param($Command)
        foreach ($prompting in 'Message', 'UserName', 'Title') {
            if (Test-IslCommandParameter -Command $Command -ParameterName $prompting) { return }
        }
        $elements = @($Command.CommandElements | Select-Object -Skip 1)
        for ($index = 0; $index -lt $elements.Count; $index++) {
            $element = $elements[$index]
            if ($element.GetType().Name -eq 'CommandParameterAst') {
                if (-not 'Credential'.StartsWith($element.ParameterName, 'OrdinalIgnoreCase')) { continue }
                if ($element.Argument) { return $element.Argument }
                if ($index + 1 -lt $elements.Count) { return $elements[$index + 1] }
                return
            }
            # A value right after another parameter belongs to that parameter
            $previous = if ($index -gt 0) { $elements[$index - 1] } else { $null }
            $taken = $previous -and $previous.GetType().Name -eq 'CommandParameterAst' -and -not $previous.Argument
            if (-not $taken) { return $element }
        }
    }

    $credentialType = '^(System\.Management\.Automation\.)?PSCredential$'

    # How an expression builds a credential, when it can only ever produce one: the constructor,
    # New-Object with the type, a cast, or Import-Clixml, which hands back a credential that
    # Export-Clixml wrote. Nothing for anything else, a member or a call included
    function Get-CredentialSource {
        param($Expression)
        # Parentheses, a one-element pipeline and the expression statement around a value are wrappers
        $unwrapped = $false
        while ($Expression -and -not $unwrapped) {
            $kind = $Expression.GetType().Name
            if ($kind -eq 'ParenExpressionAst') { $Expression = $Expression.Pipeline }
            elseif ($kind -eq 'PipelineAst' -and @($Expression.PipelineElements).Count -eq 1) {
                $Expression = $Expression.PipelineElements[0]
            }
            elseif ($kind -eq 'CommandExpressionAst') { $Expression = $Expression.Expression }
            else { $unwrapped = $true }
        }
        if (-not $Expression) { return }
        switch ($Expression.GetType().Name) {
            'CommandAst' {
                $commandName = $Expression.GetCommandName()
                if ($commandName -eq 'Import-Clixml') { return 'Import-Clixml' }
                if ($commandName -ne 'New-Object') { return }
                $typeName = $null
                $elements = @($Expression.CommandElements | Select-Object -Skip 1)
                for ($index = 0; $index -lt $elements.Count; $index++) {
                    $element = $elements[$index]
                    if ($element.GetType().Name -eq 'CommandParameterAst') {
                        if (-not 'TypeName'.StartsWith($element.ParameterName, 'OrdinalIgnoreCase')) { continue }
                        if ($element.Argument) { $typeName = $element.Argument.Extent.Text }
                        elseif ($index + 1 -lt $elements.Count) { $typeName = $elements[$index + 1].Extent.Text }
                        break
                    }
                    $previous = if ($index -gt 0) { $elements[$index - 1] } else { $null }
                    $taken = $previous -and $previous.GetType().Name -eq 'CommandParameterAst' -and
                        -not $previous.Argument
                    if (-not $taken) { $typeName = $element.Extent.Text; break }
                }
                if ("$typeName".Trim('''"') -match $credentialType) { return 'New-Object PSCredential' }
            }
            'InvokeMemberExpressionAst' {
                $onType = $Expression.Expression.GetType().Name -eq 'TypeExpressionAst' -and
                    $Expression.Expression.TypeName.FullName -match $credentialType
                if ($onType -and "$($Expression.Member.Value)" -eq 'new') { return '[pscredential]::new()' }
            }
            'ConvertExpressionAst' {
                if ($Expression.Type.TypeName.FullName -match $credentialType) { return 'a [pscredential] cast' }
            }
        }
    }

    # How a variable comes to hold a credential, when every place the script gives it a value
    # builds one: its assignments, and a parameter typed [pscredential]. Nothing when the script
    # never gives it a value, or any one of them could be something else
    function Get-VariableCredentialSource {
        param($Variable)
        $scopePrefix = '^(script|local|private|global):'
        $variableName = $Variable.VariablePath.UserPath -replace $scopePrefix, ''
        $sources = [System.Collections.Generic.List[string]]::new()
        $assignments = Find-IslAstNode -Ast $ast -TypeName AssignmentStatementAst -Where {
            param($node)
            $target = $node.Left
            $wrapped = $target.GetType().Name -in 'ConvertExpressionAst', 'AttributedExpressionAst'
            if ($wrapped) { $target = $target.Child }
            $target.GetType().Name -eq 'VariableExpressionAst' -and
            ($target.VariablePath.UserPath -replace $scopePrefix, '') -eq $variableName
        }
        foreach ($assignment in $assignments) {
            $typed = $assignment.Left.GetType().Name -eq 'ConvertExpressionAst' -and
                $assignment.Left.Type.TypeName.FullName -match $credentialType
            $source = if ($typed) { 'a [pscredential] variable' }
            else { Get-CredentialSource -Expression $assignment.Right }
            if (-not $source) { return }
            $sources.Add($source)
        }
        $parameters = Find-IslAstNode -Ast $ast -TypeName ParameterAst -Where {
            param($node)
            $node.Name.VariablePath.UserPath -eq $variableName
        }
        foreach ($parameter in $parameters) {
            $typed = @($parameter.Attributes | Where-Object {
                    $_.GetType().Name -eq 'TypeConstraintAst' -and $_.TypeName.FullName -match $credentialType
                }).Count -gt 0
            if (-not $typed) { return }
            $sources.Add('a [pscredential] parameter')
        }
        if ($sources.Count) { @($sources | Select-Object -Unique) -join ', ' }
    }

    $alwaysPrompt = 'Read-Host', 'Pause', 'Out-GridView', 'Show-Command', 'Get-Credential'
    foreach ($command in (Find-IslCommand -Ast $ast -Name $alwaysPrompt)) {
        $name = $command.GetCommandName()
        # Get-Credential -Credential returns a credential that is already built and prompts for the
        # password of a user name. A literal is a name; an expression or variable that can only
        # hold a credential never prompts; anything else cannot be told apart here
        $handed = if ($name -eq 'Get-Credential') { Get-CredentialArgument -Command $command }
        $literalTypes = 'StringConstantExpressionAst', 'ExpandableStringExpressionAst'
        $source = if ($handed -and $handed.GetType().Name -eq 'VariableExpressionAst') {
            Get-VariableCredentialSource -Variable $handed
        }
        elseif ($handed) { Get-CredentialSource -Expression $handed }
        if ($source) {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Information'
                Context  = $Context
                Extent   = $command.Extent
                Message  = ("Get-Credential -Credential returns $($handed.Extent.Text) as it is: it comes from " +
                    "$source, so it is a credential that is already built and nothing prompts; the call " +
                    'can go')
                Evidence = $builtEvidence
                # The call returns what it was handed, so the argument stands in for it
                Fix      = @{ Replacement = $handed.Extent.Text }
            }
            New-IslFinding @findingSplat
            continue
        }
        if ($handed -and $handed.GetType().Name -notin $literalTypes) {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Warning'
                Context  = $Context
                Extent   = $command.Extent
                Message  = ('Get-Credential -Credential returns a credential that is already built and ' +
                    "prompts for the password of a user name: if $($handed.Extent.Text) can ever be a " +
                    "name, the script hangs until the $timeout timeout")
                Evidence = $builtEvidence
            }
            New-IslFinding @findingSplat
            continue
        }
        $findingSplat = @{
            RuleName = $rule
            Severity = 'Error'
            Context  = $Context
            Extent   = $command.Extent
            Message  = "$name waits for input that never comes; the script hangs until the $timeout timeout"
            Evidence = $evidence
        }
        New-IslFinding @findingSplat
    }

    $hostPrompts = Find-IslAstNode -Ast $ast -TypeName InvokeMemberExpressionAst -Where {
        param($node)
        $member = "$($node.Member.Value)"
        ($member -in 'ReadLine', 'ReadKey', 'Prompt', 'PromptForChoice', 'PromptForCredential') -and
        ($node.Expression.Extent.Text -match '(?i)console|host|RawUI|\bUI\b')
    }
    foreach ($node in $hostPrompts) {
        $findingSplat = @{
            RuleName = $rule
            Severity = 'Error'
            Context  = $Context
            Extent   = $node.Extent
            Message  = ("$($node.Expression.Extent.Text).$($node.Member.Value)() waits for input; the script " +
                "hangs until the $timeout timeout")
            Evidence = $evidence
        }
        New-IslFinding @findingSplat
    }

    # Cmdlets that confirm unless told not to
    $confirming = @{
        'Set-ExecutionPolicy'     = 'Force'
        'Install-Module'          = 'Force'
        'Install-PackageProvider' = 'Force'
        'Install-Package'         = 'Force'
        'Update-Module'           = 'Force'
        'Uninstall-Module'        = 'Force'
        'Register-PSRepository'   = ''
    }
    foreach ($commandName in $confirming.Keys) {
        foreach ($command in (Find-IslCommand -Ast $ast -Name $commandName)) {
            $forced = $confirming[$commandName] -and
                (Test-IslCommandParameter -Command $command -ParameterName $confirming[$commandName])
            $silenced = $forced -or ($command.Extent.Text -match '(?i)-Confirm:\s*\$false')
            if (-not $silenced) {
                $findingSplat = @{
                    RuleName = $rule
                    Severity = 'Warning'
                    Context  = $Context
                    Extent   = $command.Extent
                    Message  = ("$commandName can prompt for confirmation (or to trust a repository); add " +
                        "-Force / -Confirm:`$false or it hangs until the $timeout timeout")
                    Evidence = $evidence
                }
                # The switch the message asks for, added to the call. Set-ExecutionPolicy gets none: the
                # agent launches with -ExecutionPolicy Bypass, and IslExecutionPolicyCall removes the call
                if ($commandName -ne 'Set-ExecutionPolicy') {
                    $switch = if ($confirming[$commandName]) { " -$($confirming[$commandName])" }
                    else { ' -Confirm:$false' }
                    $findingSplat.Fix = @{ Replacement = $command.Extent.Text + $switch }
                }
                New-IslFinding @findingSplat
            }
        }
    }
}
