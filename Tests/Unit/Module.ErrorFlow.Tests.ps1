#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    How a failure travels through the module, checked on the syntax trees of its functions.

    A function that ends with $PSCmdlet.ThrowTerminatingError() ends only itself. The function that
    called it carries on at its next statement, with nothing where the result should be, unless the
    call sits inside a try that has a catch. A throw is different: it ends every function above it.
    No test of behaviour shows the difference reliably, because a caller that goes on with nothing
    often returns nothing as well, and Should-Throw runs its call inside a try, where every error
    travels all the way up. So the rule is checked as a rule: no call to a function that can end
    with ThrowTerminatingError outside a try with a catch.

    The module is being moved from throw to ThrowTerminatingError one area at a time (#64). The
    calls that still rely on a throw in the function they call are listed below, and the list has
    to match what is in the code exactly, so it shrinks with every area that is converted.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

    function Get-ErrorFlowCall {
        <#
        .SYNOPSIS
            Lists the calls between module functions that are not inside a try with a catch.

        .DESCRIPTION
            Every function of Public, Private and Private\Rules is a node, and so is every function
            nested in one of them. A node can fail when it has a throw outside a try with a catch,
            when it calls ThrowTerminatingError, or when it makes an unguarded call to a node that
            can fail. Returns one object for each unguarded call to a node that can fail, with
            Caller, Callee, Call (both names) and EndsQuietly: whether the callee ends with
            ThrowTerminatingError, which lets the caller carry on.

            A call is guarded when it is inside a try that has a catch. A call made in a nested
            function is guarded as well when every call of that nested function is: an error
            raised below a try travels up to its catch through every function in between.

        .PARAMETER ModuleRoot
            The folder that holds Public and Private.

        .EXAMPLE
            Get-ErrorFlowCall -ModuleRoot $script:ModuleRoot

            The unguarded calls in the module.

        .INPUTS
            None.

        .OUTPUTS
            System.Management.Automation.PSCustomObject.
        #>
        [CmdletBinding()]
        [OutputType([System.Management.Automation.PSCustomObject])]
        param(
            [Parameter(Mandatory)]
            [string]$ModuleRoot
        )

        $functionType = [System.Management.Automation.Language.FunctionDefinitionAst]
        $nodes = @{}
        $topLevelOf = @{}
        foreach ($folder in 'Public', 'Private', 'Private\Rules') {
            $folderPath = Join-Path -Path $ModuleRoot -ChildPath $folder
            foreach ($file in Get-ChildItem -LiteralPath $folderPath -Filter '*.ps1' -File) {
                $tree = [System.Management.Automation.Language.Parser]::ParseFile(
                    $file.FullName, [ref]$null, [ref]$null)
                foreach ($statement in $tree.EndBlock.Statements) {
                    if ($statement -isnot $functionType) {
                        continue
                    }
                    $nodes[$statement.Name] = $statement
                    $topLevelOf[$statement] = $statement.Name
                    $nested = $statement.FindAll({ param($node) $node -is $functionType }, $true) |
                        Where-Object { $_ -ne $statement }
                    foreach ($definition in $nested) {
                        $nodes["$($statement.Name)::$($definition.Name)"] = $definition
                        $topLevelOf[$definition] = $statement.Name
                    }
                }
            }
        }

        # The function a node of the tree belongs to, and whether a try with a catch stands
        # between the node and that function
        $describe = {
            param($Node)
            $guarded = $false
            $child = $Node
            $current = $Node.Parent
            while ($null -ne $current -and $current -isnot $functionType) {
                $isTry = $current -is [System.Management.Automation.Language.TryStatementAst]
                if ($isTry -and $current.CatchClauses.Count -gt 0 -and $current.Body -eq $child) {
                    $guarded = $true
                }
                $child = $current
                $current = $current.Parent
            }
            [pscustomobject]@{ Owner = $current; Guarded = $guarded }
        }

        $canFail = @{}
        $endsQuietly = @{}
        $calls = [System.Collections.Generic.List[object]]::new()
        foreach ($name in $nodes.Keys) {
            $definition = $nodes[$name]
            $topLevel = $topLevelOf[$definition]
            foreach ($node in $definition.FindAll({ $true }, $true)) {
                if ($node -is [System.Management.Automation.Language.ThrowStatementAst]) {
                    $place = & $describe $node
                    if ($place.Owner -eq $definition -and -not $place.Guarded) {
                        $canFail[$name] = $true
                    }
                } elseif ($node -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
                    $isTerminating = "$($node.Member.Extent.Text)" -eq 'ThrowTerminatingError'
                    if ($isTerminating -and (& $describe $node).Owner -eq $definition) {
                        $canFail[$name] = $true
                        $endsQuietly[$name] = $true
                    }
                } elseif ($node -is [System.Management.Automation.Language.CommandAst]) {
                    $place = & $describe $node
                    if ($place.Owner -ne $definition) {
                        continue
                    }
                    $commandName = $node.GetCommandName()
                    $callee = $null
                    if ($commandName -and $nodes.ContainsKey("${topLevel}::$commandName")) {
                        $callee = "${topLevel}::$commandName"
                    } elseif ($commandName -and $nodes.ContainsKey($commandName)) {
                        $callee = $commandName
                    }
                    if ($null -ne $callee -and $callee -ne $name) {
                        $calls.Add([pscustomobject]@{ Caller = $name; Callee = $callee; Guarded = $place.Guarded })
                    }
                }
            }
        }

        # A try covers what the nested functions called inside it call in turn. A nested function
        # is covered when it is called at all and every call of it is guarded, or made by a nested
        # function that is covered itself
        $covered = @{}
        foreach ($name in $nodes.Keys) {
            if ($name -like '*::*' -and @($calls | Where-Object { $_.Callee -eq $name }).Count -gt 0) {
                $covered[$name] = $true
            }
        }
        do {
            $changed = $false
            foreach ($call in $calls) {
                $isCovered = $call.Guarded -or $covered.ContainsKey($call.Caller)
                if (-not $isCovered -and $covered.ContainsKey($call.Callee)) {
                    $covered.Remove($call.Callee)
                    $changed = $true
                }
            }
        } while ($changed)
        foreach ($call in $calls) {
            if ($covered.ContainsKey($call.Caller)) {
                $call.Guarded = $true
            }
        }

        # A function that makes an unguarded call to one that can fail can fail itself
        do {
            $changed = $false
            foreach ($call in $calls) {
                if (-not $call.Guarded -and $canFail.ContainsKey($call.Callee) -and
                    -not $canFail.ContainsKey($call.Caller)) {
                    $canFail[$call.Caller] = $true
                    $changed = $true
                }
            }
        } while ($changed)

        $seen = @{}
        foreach ($call in $calls) {
            $text = "$($call.Caller) -> $($call.Callee)"
            if ($call.Guarded -or -not $canFail.ContainsKey($call.Callee) -or $seen.ContainsKey($text)) {
                continue
            }
            $seen[$text] = $true
            [pscustomobject]@{
                Caller = $call.Caller
                Callee = $call.Callee
                Call = $text
                EndsQuietly = $endsQuietly.ContainsKey($call.Callee)
            }
        }
    }

    $script:Unguarded = @(Get-ErrorFlowCall -ModuleRoot $script:ModuleRoot)
}

Describe 'How a failure travels through the module' -Tag 'Unit', 'Contract' {

    It 'finds the module''s functions and the calls between them' {
        # Guards the two tests below against an analysis that found nothing to check
        $script:Unguarded.Count | Should-BeGreaterThan 0
        @($script:Unguarded | Where-Object { $_.Caller -eq 'Get-IntuneAgentTimeline' }) |
            Should-BeCollection -Count 0
    }

    It 'never calls a function that ends with ThrowTerminatingError outside a try with a catch' {
        # The caller would carry on with nothing where the result should be
        $quiet = @($script:Unguarded | Where-Object { $_.EndsQuietly } | ForEach-Object { $_.Call } | Sort-Object)

        $quiet | Should-BeCollection @()
    }

    It 'lists every call that still relies on a throw in the function it calls, and no other' {
        # Not yet converted (#64). A line goes when its caller gets the try and the catch; a new
        # line is a call that was added without them
        $pending = @(
            'Assert-BeIntuneApplicable -> Test-IslPesterAssertionSupport'
            'Assert-BeIntuneDetected -> Test-IslPesterAssertionSupport'
            'Assert-HaveIntuneRunState -> Test-IslPesterAssertionSupport'
            'Assert-HaveIntuneStatus -> Test-IslPesterAssertionSupport'
            'Assert-NotBeIntuneApplicable -> Test-IslPesterAssertionSupport'
            'Assert-NotBeIntuneDetected -> Test-IslPesterAssertionSupport'
            'Assert-PassIntuneAnalysis -> Test-IntuneScript'
            'Assert-PassIntuneAnalysis -> Test-IslPesterAssertionSupport'
            'Compare-IntuneDeployedScript -> Compare-IntuneDeployedScript::Compare-Role'
            'Compare-IntuneDeployedScript -> Compare-IntuneDeployedScript::Get-WantedPolicy'
            'Compare-IntuneDeployedScript -> Invoke-IslGraphRequest'
            'Compare-IntuneDeployedScript::Compare-Role -> Compare-IntuneDeployedScript::Compare-Setting'
            'Compare-IntuneDeployedScript::Compare-Setting -> Compare-IntuneDeployedScript::Get-LocalSetting'
            'Compare-IntuneDeployedScript::Get-LocalSetting -> Get-IslSetting'
            'Compare-IntuneDeployedScript::Get-WantedPolicy -> Invoke-IslGraphRequest'
            'Get-IntuneScriptHealth -> Compare-IntuneDeployedScript'
            'Get-IntuneScriptHealth -> Get-IntuneScriptHealth::Get-WantedPolicy'
            'Get-IntuneScriptHealth -> Invoke-IslGraphRequest'
            'Get-IntuneScriptHealth -> Test-IntuneDeployedScript'
            'Get-IntuneScriptHealth::Get-WantedPolicy -> Invoke-IslGraphRequest'
            'Get-IslExportReport -> Invoke-IslGraphRequest'
            'Get-IslSetting -> Get-IslSetting::ConvertTo-SettingsObject'
            'Invoke-IslGraphRequest -> Invoke-IslGraphRequest::Invoke-Once'
            'Repair-IntuneScript -> Test-IntuneScript'
            'Test-IntuneAssignmentFilter -> Get-IslFilterDeviceFact'
            'Test-IntuneDeployedScript -> Invoke-IslGraphRequest'
            'Test-IntuneDeployedScript -> Test-IntuneDeployedScript::Get-WantedPolicy'
            'Test-IntuneDeployedScript -> Test-IntuneDeployedScript::Test-PolicyScript'
            'Test-IntuneDeployedScript::Get-WantedPolicy -> Invoke-IslGraphRequest'
            'Test-IntuneDeployedScript::Test-PolicyScript -> Test-IntuneScript'
            'Test-IntuneScript -> Get-IslSetting'
            'Test-IntuneWin32Requirement -> Get-IslWindowsReleaseBuild'
            'Test-IntuneWin32Rule -> ConvertFrom-IslRuleSpec'
        )
        $relying = @($script:Unguarded | Where-Object { -not $_.EndsQuietly } | ForEach-Object { $_.Call })

        @($relying | Where-Object { $_ -notin $pending } | Sort-Object) | Should-BeCollection @()
        @($pending | Where-Object { $_ -notin $relying } | Sort-Object) | Should-BeCollection @()
    }
}
