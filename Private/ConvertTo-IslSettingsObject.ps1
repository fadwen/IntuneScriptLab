function ConvertTo-IslSettingsObject {
    <#
    .SYNOPSIS
    Validates a settings table and converts it to the settings object the analysis reads.

    .DESCRIPTION
    The table is the content of an IntuneScriptLab.settings.psd1 file or a hashtable passed as
    -Settings. Every key is optional. A key the module does not know is named in a warning and
    otherwise ignored. A value outside its set ends the function with the error SettingsInvalid,
    which names the source and the first value that is wrong, checked in this order:
    MinimumSeverity, ScriptType, Context, Architecture, Severity, which must be a hashtable, then
    the entries of Severity.

    .PARAMETER Table
    The settings, in the shape of a settings file.

    .PARAMETER Source
    Where the table came from, for the messages: the path of the file, '-Settings', or an empty
    string for the empty settings that apply when no file is found.

    .EXAMPLE
    $table = @{ MinimumSeverity = 'Warning'; ExcludeRule = 'IslLongSleep' }
    ConvertTo-IslSettingsObject -Table $table -Source '-Settings'

    A settings object whose MinimumSeverity is Warning and whose ExcludeRule holds IslLongSleep.

    .INPUTS
    None.

    .OUTPUTS
    IntuneScriptLab.Settings. Source, ExcludeRule, IncludeRule, MinimumSeverity, Severity,
    ScriptType, Context, Architecture and EnforceSignatureCheck.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.Settings')]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [hashtable]$Table,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Source
    )

    $validTypes = 'Detection', 'Remediation', 'PlatformScript', 'Win32Detection', 'Win32Requirement'
    $validSeverities = 'Information', 'Warning', 'Error'
    $knownKeys = 'ExcludeRule', 'IncludeRule', 'MinimumSeverity', 'Severity', 'ScriptType', 'Context',
    'Architecture', 'EnforceSignatureCheck'

    $unknown = @($Table.Keys | Where-Object { $_ -notin $knownKeys })
    if ($unknown) {
        Write-Warning "Unknown settings key(s) in ${Source}: $($unknown -join ', ')"
    }
    # Every key is optional. An index reads a key that is not there as $null, where member
    # access is an error under strict mode
    $minimumSeverity = $Table['MinimumSeverity']
    $scriptType = $Table['ScriptType']
    $context = $Table['Context']
    $architecture = $Table['Architecture']
    $severityTable = $Table['Severity']
    # The first value that is wrong is the one reported
    $problem = $null
    if ($minimumSeverity -and "$minimumSeverity" -notin $validSeverities) {
        $problem = "MinimumSeverity must be one of $($validSeverities -join ', ')"
    } elseif ($scriptType -and "$scriptType" -notin $validTypes) {
        $problem = "ScriptType must be one of $($validTypes -join ', ')"
    } elseif ($context -and "$context" -notin 'System', 'User') {
        $problem = 'Context must be System or User'
    } elseif ($architecture -and "$architecture" -notin 'x86', 'x64', 'arm64') {
        $problem = 'Architecture must be x86, x64 or arm64'
    } elseif ($severityTable -and $severityTable -isnot [System.Collections.IDictionary]) {
        $problem = 'Severity must be a hashtable of rule names and severities'
    }
    $severity = @{}
    $severityKeys = @()
    if ($severityTable -is [System.Collections.IDictionary]) {
        $severityKeys = @($severityTable.Keys | Where-Object { $null -ne $_ })
    }
    foreach ($key in $severityKeys) {
        if ($null -eq $problem -and "$($severityTable[$key])" -notin $validSeverities) {
            $problem = "Severity for $key must be one of $($validSeverities -join ', ')"
        }
        $severity[$key] = "$($severityTable[$key])"
    }
    if ($null -ne $problem) {
        $recordSplat = @{
            Message = "${Source}: $problem"
            ErrorId = 'SettingsInvalid'
            Category = [System.Management.Automation.ErrorCategory]::InvalidData
            TargetObject = $Source
        }
        $PSCmdlet.ThrowTerminatingError((New-IslErrorRecord @recordSplat))
    }

    $signatureCheck = $null
    if ($Table.ContainsKey('EnforceSignatureCheck')) {
        $signatureCheck = [bool]$Table['EnforceSignatureCheck']
    }
    [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.Settings'
        Source = $Source
        ExcludeRule = @($Table['ExcludeRule'] | Where-Object { $_ })
        IncludeRule = @($Table['IncludeRule'] | Where-Object { $_ })
        MinimumSeverity = if ($minimumSeverity) { "$minimumSeverity" } else { $null }
        Severity = $severity
        ScriptType = if ($scriptType) { "$scriptType" } else { $null }
        Context = if ($context) { "$context" } else { $null }
        Architecture = if ($architecture) { "$architecture" } else { $null }
        EnforceSignatureCheck = $signatureCheck
    }
}
