function Invoke-IslWin32DetectionPass {
    <#
    .SYNOPSIS
    Runs one detection pass of a Win32 app: its detection script and its rules.

    .DESCRIPTION
    For Invoke-IntuneWin32AppTest, for the app itself or for a dependency or a superseded app.
    The app counts as detected only when the script and every rule say installed
    (W32-MULTI-ONEFALSE, W32-MULTI-BOTHTRUE). Each rule that is not met adds a warning to the
    list it is given.

    A script that cannot be run, or a rule that cannot be read, ends the function with its
    error. An entry of -Rule that is null ends it with DetectionRuleEmpty, and a pass with
    neither a script nor a rule with DetectionMissing: either would read as detected.
    Invoke-IntuneDetectionTest reports a script it cannot run without ending, so it is called
    with -ErrorAction Stop: with nothing returned, the app would read as detected.

    .PARAMETER Phase
    Pre or Post, for the warnings.

    .PARAMETER Path
    The detection script. Left out or empty, the pass has no script.

    .PARAMETER Rule
    The detection rules, as hashtables for Test-IntuneWin32Rule -Rule.

    .PARAMETER Label
    Text that names the app in the warnings, such as " for dependency Runtime"; empty for the
    app under test.

    .PARAMETER Detection
    The parameters of Invoke-IntuneDetectionTest that every pass shares: Architecture, Context,
    TimeoutSeconds, EnforceSignatureCheck and, for another account, Credential.

    .PARAMETER Warning
    The list the warnings of the run are collected in.

    .EXAMPLE
    $passSplat = @{ Detection = $detectionSplat; Warning = $warnings }
    $pre = Invoke-IslWin32DetectionPass -Phase 'Pre' -Path $DetectionPath -Rule $DetectionRule @passSplat

    The detection before the install.

    .INPUTS
    None.

    .OUTPUTS
    IntuneScriptLab.Win32DetectionPass. Detected, TimedOut, Script, Rules and Reason.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.Win32DetectionPass')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Pre', 'Post')]
        [string]$Phase,

        [Parameter()]
        [string]$Path,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [hashtable[]]$Rule,

        [Parameter()]
        [string]$Label = '',

        [Parameter(Mandatory)]
        [hashtable]$Detection,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Warning
    )

    # A null entry is a rule that is missing, not one to leave out
    $entries = @(if ($null -ne $Rule) { $Rule })
    $problem = $null
    for ($index = 0; $index -lt $entries.Count; $index++) {
        if ($null -eq $entries[$index]) {
            $problem = @{ Id = 'DetectionRuleEmpty'; Text = "Detection rule $($index + 1)$Label is empty" }
            break
        }
    }
    if ($null -eq $problem -and -not $Path -and $entries.Count -eq 0) {
        $problem = @{ Id = 'DetectionMissing'; Text = "The $Phase detection$Label has no script and no rules" }
    }
    if ($null -ne $problem) {
        $recordSplat = @{
            Message = $problem['Text']
            ErrorId = $problem['Id']
            Category = [System.Management.Automation.ErrorCategory]::InvalidArgument
            TargetObject = $Rule
        }
        $PSCmdlet.ThrowTerminatingError((New-IslErrorRecord @recordSplat))
    }

    $scriptResult = $null
    try {
        if ($Path) {
            $detectionRun = @{ Path = $Path; ErrorAction = 'Stop' }
            $scriptResult = Invoke-IntuneDetectionTest @detectionRun @Detection @script:IslInternal
        }
        $rules = @(foreach ($entry in $entries) {
                Test-IntuneWin32Rule -Rule $entry -RuleType Detection -ErrorAction Stop
            })
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }

    $unmet = @($rules | Where-Object { -not $_.Met })
    $detected = ($null -eq $scriptResult -or $scriptResult.Detected) -and $unmet.Count -eq 0
    $timedOut = $null -ne $scriptResult -and $scriptResult.TimedOut
    foreach ($miss in $unmet) {
        $Warning.Add("$Phase detection rule not met$Label ($($miss.Kind) $($miss.Operation)): " + $miss.Reason)
    }
    $reason = if ($scriptResult -and -not $scriptResult.Detected) {
        $scriptResult.Reason
    } elseif ($unmet.Count) {
        ($unmet | ForEach-Object { $_.Reason }) -join '; '
    } else {
        'Script and rules all report installed'
    }
    [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.Win32DetectionPass'
        Detected = $detected
        TimedOut = $timedOut
        Script = $scriptResult
        Rules = $rules
        Reason = $reason
    }
}
