function Find-IslArchitectureIssue {
    <#
    .SYNOPSIS
        Flags paths that WOW64 redirects when the script runs in the 32-bit host.

    .DESCRIPTION
        Remediations and platform scripts default to the 32-bit host in the portal (Win32
        detection defaults to 64-bit). In a 32-bit process on 64-bit Windows, HKLM:\SOFTWARE
        silently becomes HKLM:\SOFTWARE\WOW6432Node, "Program Files" becomes "Program Files
        (x86)" and System32 becomes SysWOW64. The classic symptom: the remediation "fixes" a value
        in WOW6432Node, and a 64-bit detection never sees it.

    .PARAMETER Context
        The IntuneScriptLab.ScriptContext from Get-IslScriptContext: AST, tokens, bytes and the
        effective ScriptType, Context and Architecture.

    .EXAMPLE
        Find-IslArchitectureIssue -Context (Get-IslScriptContext -Path .\Detect.ps1)

        The findings this rule produces for one script, as IntuneScriptLab.Finding objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $rule = 'IslArchitectureIssue'
    $ast = $Context.Ast
    $text = $ast.Extent.Text
    $guarded = $text -match ('(?i)Is64BitProcess|Is64BitOperatingSystem|sysnative|PROCESSOR_ARCHITEW6432|' +
        'RegistryView\]::Registry64|OpenBaseKey')

    if ($Context.Architecture -eq 'x86') {
        $evidence = ('runAs32Bit launched C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe with ' +
            'Is64BitProcess=False (PS-PROBE-SYS32, REM-PROBE-SYS32, W32-DET-32)')
        $severity = if ($guarded) { 'Information' } else { 'Warning' }
        $suffix = if ($guarded) { ' (the script checks bitness, so this may be intended)' } else { '' }

        foreach ($literal in (Get-IslStringLiteral -Ast $ast)) {
            $value = $literal.Value
            if ($value -match ('(?i)^(HKLM:|Registry::HKEY_LOCAL_MACHINE|' +
                'HKEY_LOCAL_MACHINE)\\SOFTWARE\\(?!WOW6432Node)')) {
                $findingSplat = @{
                    RuleName = $rule
                    Severity = $severity
                    Context  = $Context
                    Extent   = $literal.Extent
                    Message  = ('HKLM:\SOFTWARE is redirected to HKLM:\SOFTWARE\WOW6432Node in the 32-bit ' +
                        "host$suffix. Run the script in 64-bit or open the key with RegistryView.Registry64")
                    Evidence = $evidence
                }
                New-IslFinding @findingSplat
            }
            elseif ($value -match '(?i)\\Program Files\\|^C:\\Program Files$') {
                $findingSplat = @{
                    RuleName = $rule
                    Severity = $severity
                    Context  = $Context
                    Extent   = $literal.Extent
                    Message  = ("'Program Files' resolves to 'Program Files (x86)' via the 32-bit " +
                        "environment$suffix. Use `${env:ProgramW6432} or run in 64-bit")
                    Evidence = $evidence
                }
                New-IslFinding @findingSplat
            }
            elseif ($value -match '(?i)\\System32\\' -and $value -notmatch '(?i)SysWOW64|sysnative') {
                $findingSplat = @{
                    RuleName = $rule
                    Severity = $severity
                    Context  = $Context
                    Extent   = $literal.Extent
                    Message  = ("System32 is redirected to SysWOW64 in the 32-bit host$suffix. " +
                        'Use Sysnative or run in 64-bit')
                    Evidence = $evidence
                }
                New-IslFinding @findingSplat
            }
        }
        $programFiles = Find-IslAstNode -Ast $ast -TypeName VariableExpressionAst -Where {
            param($node) $node.VariablePath.UserPath -match '(?i)^env:ProgramFiles$'
        }
        foreach ($variable in $programFiles) {
            $findingSplat = @{
                RuleName = $rule
                Severity = $severity
                Context  = $Context
                Extent   = $variable.Extent
                Message  = ("`$env:ProgramFiles is 'Program Files (x86)' in the 32-bit host$suffix. Use " +
                    "`$env:ProgramW6432 for the 64-bit folder")
                Evidence = $evidence
                # ProgramW6432 is set in 32-bit and 64-bit processes alike on a 64-bit Windows
                Fix      = @{ Replacement = ($variable.Extent.Text -replace '(?i)ProgramFiles', 'ProgramW6432') }
            }
            New-IslFinding @findingSplat
        }
    }

    # x64 and arm64 are both the native 64-bit host (System32); Sysnative is a WOW64-only alias
    if ($Context.Architecture -in 'x64', 'arm64' -and $text -match '(?i)sysnative') {
        $node = (Get-IslStringLiteral -Ast $ast | Where-Object { $_.Value -match '(?i)sysnative' } |
            Select-Object -First 1)
        $findingSplat = @{
            RuleName = $rule
            Severity = 'Warning'
            Context  = $Context
            Extent   = $(if ($node) { $node.Extent } else { $ast.Extent })
            Message  = 'Sysnative only exists for 32-bit processes; in the 64-bit host the path does not exist'
            Evidence = ('64-bit host observed: System32\WindowsPowerShell\v1.0\powershell.exe, ' +
                'Is64BitProcess=True ' +
                '(PS-PROBE-SYS64); on ARM64 the native host has no Sysnative either (local survey)')
        }
        New-IslFinding @findingSplat
    }
}
