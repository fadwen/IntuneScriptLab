function Find-IslEncodingIssue {
    <#
    .SYNOPSIS
        Flags files whose bytes Windows PowerShell 5.1 will decode as something other than UTF-8.

    .DESCRIPTION
        Intune delivers the script bytes unchanged. Without a UTF-8 BOM, Windows PowerShell 5.1
        reads the file as ANSI, so every non-ASCII character in the source is corrupted before
        the script runs ("Grüße — ✓" became "GrÃ¼ÃŸe â€" âœ""). With a BOM the source decodes
        correctly, but text the script *outputs* still goes through the OEM console code page on
        its way to Intune and loses anything outside it.

    .PARAMETER Context
        The IntuneScriptLab.ScriptContext from Get-IslScriptContext: AST, tokens, bytes and the
        effective ScriptType, Context and Architecture.

    .EXAMPLE
        Find-IslEncodingIssue -Context (Get-IslScriptContext -Path .\Detect.ps1)

        The findings this rule produces for one script, as IntuneScriptLab.Finding objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $rule = 'IslEncodingIssue'
    $bytes = $Context.Bytes
    if (-not $bytes -or $bytes.Length -eq 0) { return }

    $hasUtf8Bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $isUtf16 = $bytes.Length -ge 2 -and
        (($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF))
    $hasNonAscii = $false
    foreach ($byte in $bytes) { if ($byte -gt 0x7F) { $hasNonAscii = $true; break } }

    if ($isUtf16) {
        $findingSplat = @{
            RuleName = $rule
            Severity = 'Warning'
            Context  = $Context
            Extent   = $Context.Ast.Extent
            Message  = 'File is UTF-16. Intune expects UTF-8; save as UTF-8 with BOM'
            Evidence = ('Microsoft Learn: "Ensure the scripts are encoded in UTF-8"; files are delivered ' +
                'byte-for-byte')
            Fix      = @{ Encoding = 'UTF8BOM' }
        }
        New-IslFinding @findingSplat
        return
    }

    if ($hasNonAscii -and -not $hasUtf8Bom) {
        $findingSplat = @{
            RuleName = $rule
            Severity = 'Warning'
            Context  = $Context
            Extent   = $Context.Ast.Extent
            Message  = ('Non-ASCII characters in a UTF-8 file without a BOM: Windows PowerShell 5.1 decodes ' +
                'it as ANSI and corrupts them. Save as UTF-8 with BOM')
            Evidence = ('Same bytes uploaded with and without BOM: without, the literal "Grüße — ✓" ran as ' +
                '"GrÃ¼ÃŸe â€" âœ"" (REM-ENC-BOM vs REM-PROBE-SYS64)')
            Fix      = @{ Encoding = 'UTF8BOM' }
        }
        New-IslFinding @findingSplat
    }

    if ($hasNonAscii -and $Context.ScriptType -in 'Detection', 'Remediation', 'Win32Detection') {
        $literals = Get-IslStringLiteral -Ast $Context.Ast | Where-Object { $_.Value -match '[^\x00-\x7F]' } |
            Select-Object -First 1
        if ($literals) {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Information'
                Context  = $Context
                Extent   = $literals.Extent
                Message  = ('Non-ASCII text in output is mangled on the way to Intune (OEM code page); keep ' +
                    'reported output ASCII')
                Evidence = ('With a BOM the script ran correctly, but Intune reported "Grüße - √" for ' +
                    '"Grüße — ✓" (REM-ENC-BOM)')
            }
            New-IslFinding @findingSplat
        }
    }
}
