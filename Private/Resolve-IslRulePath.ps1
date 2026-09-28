function Resolve-IslRulePath {
    <#
    .SYNOPSIS
        Expands a file rule's path the way the agent does, in the 64-bit or the 32-bit context.

    .DESCRIPTION
        A file rule's path may hold %VARIABLE% references. The agent expands them in the 64-bit
        context by default, so %ProgramFiles% is C:\Program Files even though the agent itself is a
        32-bit process; with check32BitOn64System it expands them in the 32-bit context, where
        %ProgramFiles% and %CommonProgramFiles% are the (x86) folders (W32-FILE-PF-32 found a file
        that only existed under Program Files (x86); W32-FILE-PF-64 did not). On a 32-bit device
        there is only one context.

    .PARAMETER Path
        The folder part of the rule, with or without %VARIABLE% references.

    .PARAMETER Check32BitOn64System
        Expand in the 32-bit context on a 64-bit device.

    .EXAMPLE
        Resolve-IslRulePath -Path '%ProgramFiles%\Vendor' -Check32BitOn64System $true

        C:\Program Files (x86)\Vendor on a 64-bit device.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [bool]$Check32BitOn64System
    )

    $expanded = $Path
    if ($Check32BitOn64System -and [Environment]::Is64BitOperatingSystem) {
        # The variables whose value differs between the two contexts, substituted before the general
        # expansion so the rest of the string still expands normally
        $x86ProgramFiles = ${env:ProgramFiles(x86)}
        $x86Common = ${env:CommonProgramFiles(x86)}
        if ($x86ProgramFiles) { $expanded = $expanded -replace '(?i)%ProgramFiles%', $x86ProgramFiles }
        if ($x86Common) { $expanded = $expanded -replace '(?i)%CommonProgramFiles%', $x86Common }
    }
    [Environment]::ExpandEnvironmentVariables($expanded)
}
