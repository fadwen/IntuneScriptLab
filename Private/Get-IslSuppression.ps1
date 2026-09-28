function Get-IslSuppression {
    <#
    .SYNOPSIS
        Reads the Suppress directives of a script: which rules are silenced, and where.

    .DESCRIPTION
        A directive comment can carry Suppress=Rule1,Rule2 (wildcards allowed). Where the comment
        sits decides its reach:

            - in the header, before the first statement: the whole file
            - on its own line in the body: the next line that holds code
            - at the end of a line of code: that line

        Returns one IntuneScriptLab.Suppression per rule name with the line it applies to, 0 for
        the whole file. Test-IntuneScript drops the findings these match unless -IncludeSuppressed
        asks for them.

    .PARAMETER Context
        The IntuneScriptLab.ScriptContext from Get-IslScriptContext (its tokens are read).

    .EXAMPLE
        Get-IslSuppression -Context (Get-IslScriptContext -Path .\Detect.ps1)

        The suppressions declared in Detect.ps1.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.Suppression')]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $tokens = @($Context.Tokens)
    $code = @($tokens | Where-Object { $_.Kind -notin 'Comment', 'NewLine', 'LineContinuation', 'EndOfInput' })
    $firstCodeLine = if ($code) { $code[0].Extent.StartLineNumber } else { [int]::MaxValue }

    foreach ($token in $tokens) {
        if ($token.Kind -ne 'Comment') { continue }
        if ($token.Text -notmatch '(?m)^\s*#\s*IntuneScriptLab\s*:\s*(.+)$') { continue }
        if ($Matches[1] -notmatch 'Suppress=([^\s;]+)') { continue }
        $rules = @($Matches[1] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $line = $token.Extent.StartLineNumber
        $codeBefore = @($code | Where-Object {
                $_.Extent.StartLineNumber -eq $line -and $_.Extent.StartOffset -lt $token.Extent.StartOffset
            })
        $scope = if ($codeBefore) { $line }
        elseif ($line -lt $firstCodeLine) { 0 }
        else {
            $next = $code | Where-Object { $_.Extent.StartLineNumber -gt $line } | Select-Object -First 1
            if ($next) { $next.Extent.StartLineNumber } else { $line }
        }
        foreach ($rule in $rules) {
            [pscustomobject]@{
                PSTypeName = 'IntuneScriptLab.Suppression'
                Rule       = $rule
                Line       = $scope
                Source     = $line
            }
        }
    }
}
