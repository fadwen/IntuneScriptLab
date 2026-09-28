function Find-IslArm64Assumption {
    <#
    .SYNOPSIS
        Flags code that equates "64-bit" with x64, which breaks on Windows on ARM.

    .DESCRIPTION
        On an ARM64 device the native host reports PROCESSOR_ARCHITECTURE=ARM64 (and the x86 host
        reports PROCESSOR_ARCHITEW6432=ARM64), Is64BitProcess is true, ProgramFiles is
        C:\Program Files and there is an extra C:\Program Files (Arm). Scripts that test for
        'AMD64' to decide they are on 64-bit Windows silently take the 32-bit branch; scripts
        that download an x64 installer get the emulated build at best and a refusal at worst.
        Applies when the target architecture is arm64.

    .PARAMETER Context
        The IntuneScriptLab.ScriptContext from Get-IslScriptContext: AST, tokens, bytes and the
        effective ScriptType, Context and Architecture.

    .EXAMPLE
        Find-IslArm64Assumption -Context (Get-IslScriptContext -Path .\Detect.ps1)

        The findings this rule produces for one script, as IntuneScriptLab.Finding objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    if ($Context.Architecture -ne 'arm64') { return }
    $rule = 'IslArm64Assumption'
    $ast = $Context.Ast
    $evidence = ('Windows 11 ARM64 host survey: System32 PowerShell is native ARM64 ' +
        ('(PROCESSOR_ARCHITECTURE=ARM64, Is64BitProcess=True), SysWOW64 is x86 (PROCESSOR_ARCHITEW6432=ARM64), ' +
            'Program Files (Arm) exists, no x64 PowerShell host'))
    $literals = @(Get-IslStringLiteral -Ast $ast)

    # 'AMD64' compared against the architecture variables
    foreach ($literal in ($literals | Where-Object { $_.Value -match '(?i)^AMD64$' })) {
        $findingSplat = @{
            RuleName = $rule
            Severity = 'Warning'
            Context  = $Context
            Extent   = $literal.Extent
            Message  = ("'AMD64' does not match on Windows on ARM (the value is ARM64), so a 64-bit " +
                "check built on it takes the 32-bit branch. Test [Environment]::Is64BitProcess or " +
                "match 'ARM64|AMD64'")
            Evidence = $evidence
        }
        New-IslFinding @findingSplat
    }

    # x64-specific installers or download URLs
    foreach ($literal in ($literals | Where-Object { $_.Value -match ('(?i)(x86_64|amd64|win64|' +
        '[_\-./]x64[_\-./]|' +
        '[_\-./]x64$)') -and $_.Value -match '(?i)https?://|\.(msi|exe|zip|msix|appx)$' })) {
        $findingSplat = @{
            RuleName = $rule
            Severity = 'Information'
            Context  = $Context
            Extent   = $literal.Extent
            Message  = ('x64-specific package: on an ARM64 device this installs the emulated x64 build, or ' +
                'fails if the installer checks the CPU. Prefer an ARM64 or architecture-neutral package ' +
                'when one exists')
            Evidence = $evidence
        }
        New-IslFinding @findingSplat
    }

    # Enumerating Program Files and Program Files (x86) misses Program Files (Arm)
    $text = $ast.Extent.Text
    if ($text -match ('(?i)Program Files ' +
        '\(x86\)|ProgramFiles\(x86\)') -and $text -notmatch '(?i)Program Files \(Arm\)|ProgramFiles\(Arm\)') {
        $node = $literals | Where-Object { $_.Value -match '(?i)Program Files \(x86\)' } | Select-Object -First 1
        $findingSplat = @{
            RuleName = $rule
            Severity = 'Information'
            Context  = $Context
            Extent   = $(if ($node) { $node.Extent } else { $ast.Extent })
            Message  = ("Program Files (x86) is checked but not 'Program Files (Arm)', where ARM64 " +
                "devices can keep 32-bit ARM apps (`${env:ProgramFiles(Arm)})")
            Evidence = $evidence
        }
        New-IslFinding @findingSplat
    }
}
