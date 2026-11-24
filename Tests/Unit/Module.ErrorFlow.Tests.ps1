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

    The module was moved from throw to ThrowTerminatingError one area at a time (#64), with a
    list here of the calls that still relied on a throw. The list is empty now and gone: a call
    to a function that can fail, by either means, has to be inside a try with a catch.
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
            can fail. Returns one object for each call to a node that can fail, with Caller,
            Callee, Call (both names), Guarded, and EndsQuietly: whether the callee ends with
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

        # One line for each pair of names, and an unguarded call wins over a guarded one
        $seen = @{}
        foreach ($call in ($calls | Sort-Object -Property Guarded)) {
            $text = "$($call.Caller) -> $($call.Callee)"
            if (-not $canFail.ContainsKey($call.Callee) -or $seen.ContainsKey($text)) {
                continue
            }
            $seen[$text] = $true
            [pscustomobject]@{
                Caller = $call.Caller
                Callee = $call.Callee
                Call = $text
                Guarded = $call.Guarded
                EndsQuietly = $endsQuietly.ContainsKey($call.Callee)
            }
        }
    }

    $script:Calls = @(Get-ErrorFlowCall -ModuleRoot $script:ModuleRoot)
}

Describe 'How a failure travels through the module' -Tag 'Unit', 'Contract' {

    It 'finds the module''s functions and the calls between them' {
        # Guards the test below against an analysis that found nothing to check
        $script:Calls.Count | Should-BeGreaterThan 40
        $launchCall = 'Invoke-IntuneDetectionTest -> Invoke-IslScriptRun'
        $launch = @($script:Calls | Where-Object { $_.Call -eq $launchCall })
        $launch | Should-BeCollection -Count 1
        $launch[0].Guarded | Should-BeTrue
        $launch[0].EndsQuietly | Should-BeTrue
    }

    It 'never calls a function that can fail outside a try with a catch' {
        # After a function that ends with ThrowTerminatingError, the caller would carry on with
        # nothing where the result should be
        $unguarded = @($script:Calls | Where-Object { -not $_.Guarded } | ForEach-Object { $_.Call } | Sort-Object)

        $unguarded | Should-BeCollection @()
    }
}

Describe 'The analysis itself, on a module of four functions' -Tag 'Unit', 'Contract' {

    BeforeAll {
        $root = Join-Path $TestDrive 'SampleModule'
        foreach ($folder in 'Public', 'Private', 'Private\Rules') {
            $null = New-Item -ItemType Directory -Path (Join-Path $root $folder) -Force
        }
        $files = @{
            'Private\Get-Inner.ps1' = @'
function Get-Inner {
    [CmdletBinding()]
    param()
    $PSCmdlet.ThrowTerminatingError($record)
}
'@
            'Public\Get-Careless.ps1' = @'
function Get-Careless {
    [CmdletBinding()]
    param()
    try { $value = Get-Inner } finally { $null = $value }
}
'@
            'Public\Get-Careful.ps1' = @'
function Get-Careful {
    [CmdletBinding()]
    param()
    function Get-Nested { Get-Inner }
    try { Get-Nested } catch { $PSCmdlet.ThrowTerminatingError($_) }
}
'@
            'Public\Get-HalfCareful.ps1' = @'
function Get-HalfCareful {
    [CmdletBinding()]
    param()
    function Get-Nested { Get-Inner }
    try { Get-Nested } catch { $PSCmdlet.ThrowTerminatingError($_) }
    Get-Nested
}
'@
        }
        foreach ($name in $files.Keys) {
            Set-Content -LiteralPath (Join-Path $root $name) -Value $files[$name] -Encoding ascii
        }
        $script:Sample = @(Get-ErrorFlowCall -ModuleRoot $root)
    }

    It 'reports a call that has only a finally around it' {
        $call = @($script:Sample | Where-Object { $_.Call -eq 'Get-Careless -> Get-Inner' })

        $call | Should-BeCollection -Count 1
        $call[0].Guarded | Should-BeFalse
        $call[0].EndsQuietly | Should-BeTrue
    }

    It 'accepts a call in a nested function when every call of that nested function is guarded' {
        $nested = @($script:Sample | Where-Object { $_.Caller -like 'Get-Careful*' })

        $nested.Count | Should-BeGreaterThan 0
        @($nested | Where-Object { -not $_.Guarded }) | Should-BeCollection @()
    }

    It 'reports the call in a nested function when one call of that nested function is not guarded' {
        $unguarded = @($script:Sample | Where-Object { $_.Caller -like 'Get-HalfCareful*' -and -not $_.Guarded } |
                ForEach-Object { $_.Call } | Sort-Object)

        $unguarded | Should-BeCollection -Count 2
        $unguarded[0] | Should-Be 'Get-HalfCareful -> Get-HalfCareful::Get-Nested'
        $unguarded[1] | Should-Be 'Get-HalfCareful::Get-Nested -> Get-Inner'
    }
}
