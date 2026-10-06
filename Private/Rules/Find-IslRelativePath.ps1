function Find-IslRelativePath {
    <#
    .SYNOPSIS
        Flags paths that depend on the working directory.

    .DESCRIPTION
        The working directory is not the script's folder. SYSTEM scripts start in
        C:\WINDOWS\system32; Win32 install commands start in the extracted content folder; and
        a user-context platform script was observed inheriting whatever folder the agent had last
        used for a Win32 install. Relative paths therefore point somewhere different on every run.

    .PARAMETER Context
        The IntuneScriptLab.ScriptContext from Get-IslScriptContext: AST, tokens, bytes and the
        effective ScriptType, Context and Architecture.

    .EXAMPLE
        Find-IslRelativePath -Context (Get-IslScriptContext -Path .\Detect.ps1)

        The findings this rule produces for one script, as IntuneScriptLab.Finding objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $rule = 'IslRelativePath'
    $evidence = ('cwd was C:\WINDOWS\system32 for SYSTEM scripts, the content folder for Win32 installs, and ' +
        'once ' +
        'an old IMECache folder for a user script (PS-PROBE-USER)')

    foreach ($literal in (Get-IslStringLiteral -Ast $Context.Ast)) {
        if ($literal.Value -match '^\.{1,2}[\\/]') {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Warning'
                Context  = $Context
                Extent   = $literal.Extent
                Message  = ("Relative path '$($literal.Value)' resolves against an unpredictable working " +
                    "directory. Anchor it to `$PSScriptRoot or use a full path")
                Evidence = $evidence
            }
            New-IslFinding @findingSplat
        }
    }
    $pwdVariables = Find-IslAstNode -Ast $Context.Ast -TypeName VariableExpressionAst -Where {
        param($node) $node.VariablePath.UserPath -eq 'PWD'
    }
    foreach ($variable in $pwdVariables) {
        $findingSplat = @{
            RuleName = $rule
            Severity = 'Information'
            Context  = $Context
            Extent   = $variable.Extent
            Message  = ('$PWD is not the script folder under Intune; use $PSScriptRoot for files shipped with ' +
                'the script')
            Evidence = $evidence
        }
        # $PSScriptRoot is a string where $PWD is a PathInfo, so $PWD.Path and the like get no edit
        if ($variable.Parent.GetType().Name -ne 'MemberExpressionAst') {
            $findingSplat.Fix = @{ Replacement = ($variable.Extent.Text -replace '(?i)PWD', 'PSScriptRoot') }
        }
        New-IslFinding @findingSplat
    }
}
