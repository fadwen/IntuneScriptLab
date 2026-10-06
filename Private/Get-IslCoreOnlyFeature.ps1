function Get-IslCoreOnlyFeature {
    <#
    .SYNOPSIS
        The cmdlets, parameters and parameter values that PowerShell 7 has and Windows PowerShell 5.1 lacks.

    .DESCRIPTION
        The table IslPowerShell7Syntax reports from, kept in one place so a test can hold it against
        both hosts: every command listed must be absent from Windows PowerShell 5.1 and present in
        PowerShell 7, every parameter likewise on its command, and every value refused by the 5.1
        parameter's ValidateSet and taken by 7's. The 0.26.0 audit found two parameters here that
        exist on neither host, and an Out-File value that the rule never matched; the test is what
        keeps that from happening again.

        A script that uses one of these parses under 5.1, so it starts: the call fails with an
        error and the script carries on to its own exit (REM-PS7-CMDLET, REM-PS7-PARAM,
        REM-PS7-ENCODING).

    .EXAMPLE
        (Get-IslCoreOnlyFeature).Parameters['ConvertFrom-Json']

        AsHashtable, Depth, NoEnumerate, DateKind.

    .OUTPUTS
        IntuneScriptLab.CoreOnlyFeature: Commands (string[]), Parameters (hashtable of command to
        parameter names) and Values (hashtable of command to hashtable of parameter to values).
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.CoreOnlyFeature')]
    param()

    [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.CoreOnlyFeature'
        # Switch-Process is not here: PowerShell 7 has it on Linux and macOS only, so a script that
        # calls it fails on both Windows hosts. Get-ChildItem -FollowSymlink is not here either:
        # Windows PowerShell 5.0 already had it. Both were listed until the test below ran
        Commands   = [string[]]@(
            'Get-Error', 'Join-String', 'Test-Json', 'ConvertFrom-Markdown', 'Get-Uptime', 'Remove-Alias',
            'Get-ExperimentalFeature', 'Get-MarkdownOption', 'Show-Markdown', 'ConvertTo-CliXml',
            'ConvertFrom-CliXml'
        )
        Parameters = @{
            'ConvertFrom-Json'  = 'AsHashtable', 'Depth', 'NoEnumerate', 'DateKind'
            'ConvertTo-Json'    = 'AsArray', 'EnumsAsStrings', 'EscapeHandling'
            'Split-Path'        = 'LeafBase', 'Extension'
            'Invoke-WebRequest' = 'SkipCertificateCheck', 'SkipHttpErrorCheck', 'Form', 'Resume',
            'Authentication', 'Token', 'AllowInsecureRedirect', 'RetryIntervalSec'
            'Invoke-RestMethod' = 'SkipCertificateCheck', 'SkipHttpErrorCheck', 'Form', 'Resume',
            'StatusCodeVariable', 'Authentication', 'Token', 'AllowInsecureRedirect', 'ResponseHeadersVariable'
            'Select-String'     = 'Raw', 'Culture', 'NoEmphasis'
            'Test-Connection'   = 'TargetName', 'TcpPort', 'Ping', 'Traceroute', 'IPv4', 'IPv6', 'Repeat'
            'Get-Content'       = 'AsByteStream'
            'Set-Content'       = 'AsByteStream'
            'Add-Content'       = 'AsByteStream'
            'Start-Process'     = 'Environment'
            'Compress-Archive'  = 'PassThru'
            'Import-Module'     = 'UseWindowsPowerShell', 'SkipEditionCheck'
        }
        # A parameter both hosts have, with a value only PowerShell 7 accepts
        Values     = @{
            'Out-File' = @{ Encoding = [string[]]@('utf8NoBOM') }
        }
    }
}
