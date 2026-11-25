function Invoke-IntuneWin32AppTest {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Runs a Win32 app's detect, install or uninstall, detect flow like the agent.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('IntuneScriptLab.Win32AppResult')]
    param(
        [string]$DetectionPath,

        # File, registry and product code rules (hashtables for Test-IntuneWin32Rule -Rule); with a
        # detection script, all of them and the script must say installed
        [hashtable[]]$DetectionRule,

        [Parameter(Mandatory)]
        [string]$ContentPath,

        [string]$InstallCommand,

        [string]$UninstallCommand,

        [ValidateSet('Install', 'Uninstall')]
        [string]$Intent = 'Install',

        # Dependencies, each a hashtable with Name, DetectionPath and/or DetectionRule, ContentPath,
        # InstallCommand and Type (autoInstall, the default, or detect), handled after this app's
        # first detection in the order given, as the agent was observed to (W32-DEP-PARENT)
        [hashtable[]]$DependsOn,

        # Superseded apps, each a hashtable with Name, DetectionPath and/or DetectionRule, ContentPath,
        # UninstallCommand and Type (update, the default, or replace); a detected replace target is
        # uninstalled before this app installs, an update target stays (W32-SUP-OLD-A, W32-SUP-OLD-B)
        [hashtable[]]$Supersedes,

        # Left out: the device's 64-bit host (x64, or arm64 on Windows on ARM), the agent's default
        [ValidateSet('x86', 'x64', 'arm64')]
        [string]$Architecture,

        [ValidateSet('User', 'System')]
        [string]$Context = 'User',

        # Run every launch (detection, requirement, install, uninstall) as this account instead of
        # the current user (with -Context User), through a scheduled task in the account's own
        # session; needs an elevated session
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential,

        # The app's install behavior in the portal (System or User); User only adds the observed
        # warning about device-targeted assignments
        [ValidateSet('System', 'User')]
        [string]$InstallContext = 'System',

        [hashtable]$ReturnCodes = @{
            0 = 'success'; 1707 = 'success'; 3010 = 'softReboot'; 1641 = 'hardReboot'; 1618 = 'retry'
        },

        [ValidateRange(1, 86400)]
        [int]$TimeoutSeconds = 300,

        [ValidateRange(1, 86400)]
        [int]$InstallTimeoutSeconds = 600,

        [switch]$EnforceSignatureCheck
    )
    Write-Verbose "Starting $($MyInvocation.MyCommand.Name) for $($PSBoundParameters.Keys -join ', ')"
    # The agent's default host is the device's 64-bit one: arm64 on Windows on ARM, where no x64
    # host exists, and x64 elsewhere
    $runArchitecture = $Architecture
    if (-not $runArchitecture) { $runArchitecture = Get-IslHostArchitecture }

    $argumentError = @{
        Category = [System.Management.Automation.ErrorCategory]::InvalidArgument
        ExceptionType = [System.ArgumentException]
    }
    if (-not $DetectionPath -and -not $DetectionRule) {
        $message = 'Give a detection script (-DetectionPath), detection rules (-DetectionRule), or both'
        $record = New-IslErrorRecord -Message $message -ErrorId 'DetectionMissing' @argumentError
        $PSCmdlet.ThrowTerminatingError($record)
    }
    $command = if ($Intent -eq 'Install') { $InstallCommand } else { $UninstallCommand }
    if (-not $command) {
        $message = "Intent $Intent needs -${Intent}Command"
        $record = New-IslErrorRecord -Message $message -ErrorId 'IntentCommandMissing' @argumentError
        $PSCmdlet.ThrowTerminatingError($record)
    }
    foreach ($related in @($DependsOn) + @($Supersedes)) {
        if (-not $related) { continue }
        if (-not $related['Name']) {
            $message = 'Every -DependsOn and -Supersedes entry needs a Name'
            $record = New-IslErrorRecord -Message $message -ErrorId 'RelatedAppNameMissing' @argumentError
            $PSCmdlet.ThrowTerminatingError($record)
        }
        if (-not $related['DetectionPath'] -and -not $related['DetectionRule']) {
            $message = "$($related['Name']) needs a DetectionPath, DetectionRule entries, or both"
            $record = New-IslErrorRecord -Message $message -ErrorId 'RelatedAppDetectionMissing' @argumentError
            $PSCmdlet.ThrowTerminatingError($record)
        }
    }
    # A null rule entry is a rule that is missing, not one to leave out. It is found here, before
    # -WhatIf is answered and any detection runs; each detection pass checks it again
    $ruleSets = @(
        @{ Rule = $DetectionRule; Label = '' }
        foreach ($related in @($DependsOn)) {
            if ($related) {
                @{ Rule = $related['DetectionRule']; Label = " for dependency $($related['Name'])" }
            }
        }
        foreach ($related in @($Supersedes)) {
            if ($related) {
                @{ Rule = $related['DetectionRule']; Label = " for superseded app $($related['Name'])" }
            }
        }
    )
    foreach ($ruleSet in $ruleSets) {
        $entries = @(if ($null -ne $ruleSet['Rule']) { $ruleSet['Rule'] })
        for ($index = 0; $index -lt $entries.Count; $index++) {
            if ($null -eq $entries[$index]) {
                $message = "Detection rule $($index + 1)$($ruleSet['Label']) is empty"
                $record = New-IslErrorRecord -Message $message -ErrorId 'DetectionRuleEmpty' @argumentError
                $PSCmdlet.ThrowTerminatingError($record)
            }
        }
    }
    # A content folder that is not there is found before anything runs
    try {
        $null = Resolve-Path -LiteralPath $ContentPath -ErrorAction Stop
        foreach ($related in @($DependsOn) + @($Supersedes)) {
            if ($related -and $related['ContentPath']) {
                $null = Resolve-Path -LiteralPath $related['ContentPath'] -ErrorAction Stop
            }
        }
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }

    $warnings = [System.Collections.Generic.List[string]]::new()
    if ($InstallContext -eq 'User') {
        # W32-USER-INSTALL: a device-group assignment never installs a user-context app on either join type
        $warnings.Add('Install behavior User: an assignment to a device group never installs the app. The ' +
            'agent logs "user install context and this is a userless check-in" and reports Not applicable ' +
            '(Applicability 1011); assign the app to users')
    }
    $detectionSplat = @{
        Architecture          = $runArchitecture
        Context               = $Context
        TimeoutSeconds        = $TimeoutSeconds
        EnforceSignatureCheck = $EnforceSignatureCheck
    }
    if ($Credential) {
        if ($Context -eq 'System') {
            $message = '-Credential applies to -Context User; System runs as NT AUTHORITY\SYSTEM'
            $record = New-IslErrorRecord -Message $message -ErrorId 'CredentialWithSystemContext' @argumentError
            $PSCmdlet.ThrowTerminatingError($record)
        }
        $detectionSplat.Credential = $Credential
    }
    # The command line and the detection script are somebody's code and are about to run: -WhatIf
    # names them and runs nothing. The detections below are part of this one run, so they do not
    # ask again
    $action = "Run the Win32 app flow for intent $Intent ($Context context, $runArchitecture): $command"
    if (-not $PSCmdlet.ShouldProcess($ContentPath, $action)) {
        return
    }

    $runAs = if ($Credential) { $Credential.UserName }
    elseif ($Context -eq 'System') { 'NT AUTHORITY\SYSTEM' }
    elseif ($env:USERDOMAIN) { "$env:USERDOMAIN\$env:USERNAME" }
    else { [Environment]::UserName }

    # What every detection pass and every install or uninstall of the flow share
    $passSplat = @{ Detection = $detectionSplat; Warning = $warnings }
    $contentSplat = @{ Context = $Context; TimeoutSeconds = $InstallTimeoutSeconds; Warning = $warnings }
    if ($Credential) { $contentSplat.Credential = $Credential }

    # The whole flow is one transaction. A step that could not be run ends it with that step's error
    try {
        $pre = Invoke-IslWin32DetectionPass -Phase 'Pre' -Path $DetectionPath -Rule $DetectionRule @passSplat
        $execution = $null
        $post = $null
        $dependencies = [System.Collections.Generic.List[object]]::new()
        $superseded = [System.Collections.Generic.List[object]]::new()
        $status = $null

        if ($pre.TimedOut) { $status = 'TimedOut' }
        elseif ($Intent -eq 'Install' -and $pre.Detected) { $status = 'Installed' }
        elseif ($Intent -eq 'Uninstall' -and -not $pre.Detected) { $status = 'Not installed' }

        # Dependencies come after this app's first detection: the child's detection, install and
        # detection, then this app again (W32-DEP-PARENT). A detect-only dependency that is absent stops
        # the parent with "1 or more dependent apps are configured to not automatically install."
        # (W32-DEPD-PARENT)
        if (-not $status -and $Intent -eq 'Install') {
            foreach ($dependency in @($DependsOn | Where-Object { $_ })) {
                $type = if ($dependency['Type']) { "$($dependency['Type'])" } else { 'autoInstall' }
                $name = "$($dependency['Name'])"
                $detect = @{
                    Path = $dependency['DetectionPath']
                    Rule = $dependency['DetectionRule']
                    Label = " for dependency $name"
                }
                $childPre = Invoke-IslWin32DetectionPass -Phase 'Pre' @detect @passSplat
                $childInstall = $null
                $childPost = $null
                $childStatus = if ($childPre.TimedOut) { 'TimedOut' }
                elseif ($childPre.Detected) { 'Installed' }
                elseif ($type -ne 'autoInstall') { 'Not detected (detect-only dependency)' }
                elseif (-not $dependency['InstallCommand'] -or -not $dependency['ContentPath']) {
                    'Not detected (no InstallCommand or ContentPath)'
                }
                else {
                    $childRun = @{
                        Phase = 'install'
                        Content = $dependency['ContentPath']
                        CommandLine = $dependency['InstallCommand']
                    }
                    $childInstall = Invoke-IslWin32ContentCommand @childRun @contentSplat
                    switch (Get-IslWin32Outcome -Run $childInstall -ReturnCodes $ReturnCodes) {
                        'timedOut' { 'TimedOut' }
                        'retry' { 'Retry' }
                        'failed' { "Install failed (exit $($childInstall.ExitCode))" }
                        default {
                            $childPost = Invoke-IslWin32DetectionPass -Phase 'Post' @detect @passSplat
                            if ($childPost.Detected) { 'Installed after install' }
                            else { 'Not detected after install' }
                        }
                    }
                }
                $relatedSplat = @{
                    Name = $name; Relationship = "dependency ($type)"; Status = $childStatus
                    Pre = $childPre; Install = $childInstall; Uninstall = $null; Post = $childPost
                }
                $dependencies.Add((ConvertTo-IslWin32RelatedResult @relatedSplat))
                if ($childStatus -notin 'Installed', 'Installed after install') {
                    $status = 'Not installed (dependency)'
                    $warnings.Add("Dependency $name ($type): $childStatus. The agent does not run this app's " +
                        'install; an absent detect-only dependency reports Not installed with "1 or more ' +
                        'dependent apps are configured to not automatically install." (W32-DEPD-PARENT)')
                    break
                }
            }
        }

        # Superseded apps are detected before this app installs; a replace target that is present is
        # uninstalled first (W32-SUP-OLD-B: old uninstall, then new install), an update target stays
        # installed (W32-SUP-OLD-A)
        if (-not $status -and $Intent -eq 'Install') {
            foreach ($old in @($Supersedes | Where-Object { $_ })) {
                $type = if ($old['Type']) { "$($old['Type'])" } else { 'update' }
                $name = "$($old['Name'])"
                $detect = @{
                    Path = $old['DetectionPath']
                    Rule = $old['DetectionRule']
                    Label = " for superseded app $name"
                }
                $oldPre = Invoke-IslWin32DetectionPass -Phase 'Pre' @detect @passSplat
                $oldUninstall = $null
                $oldPost = $null
                $oldStatus = if ($oldPre.TimedOut) { 'TimedOut' }
                elseif (-not $oldPre.Detected) { 'Not installed' }
                elseif ($type -ne 'replace') { 'Installed (left in place by update)' }
                elseif (-not $old['UninstallCommand'] -or -not $old['ContentPath']) {
                    'Installed (no UninstallCommand or ContentPath)'
                }
                else {
                    $oldRun = @{
                        Phase = 'uninstall'
                        Content = $old['ContentPath']
                        CommandLine = $old['UninstallCommand']
                    }
                    $oldUninstall = Invoke-IslWin32ContentCommand @oldRun @contentSplat
                    switch (Get-IslWin32Outcome -Run $oldUninstall -ReturnCodes $ReturnCodes) {
                        'timedOut' { 'TimedOut' }
                        'retry' { 'Retry' }
                        'failed' { "Uninstall failed (exit $($oldUninstall.ExitCode))" }
                        default {
                            $oldPost = Invoke-IslWin32DetectionPass -Phase 'Post' @detect @passSplat
                            if ($oldPost.Detected) { 'Still detected after uninstall' } else { 'Uninstalled' }
                        }
                    }
                }
                $relatedSplat = @{
                    Name = $name; Relationship = "supersedence ($type)"; Status = $oldStatus
                    Pre = $oldPre; Install = $null; Uninstall = $oldUninstall; Post = $oldPost
                }
                $superseded.Add((ConvertTo-IslWin32RelatedResult @relatedSplat))
                if ($type -eq 'replace' -and $oldStatus -notin 'Uninstalled', 'Not installed') {
                    $warnings.Add("Superseded app $name (replace): $oldStatus. The agent removes a replace " +
                        'target before it installs the new app (W32-SUP-OLD-B), so the old app would still ' +
                        'be present')
                }
            }
        }

        if (-not $status) {
            $appRun = @{ Phase = $Intent.ToLower(); Content = $ContentPath; CommandLine = $command }
            $execution = Invoke-IslWin32ContentCommand @appRun @contentSplat
            $outcome = Get-IslWin32Outcome -Run $execution -ReturnCodes $ReturnCodes
            switch ($outcome) {
                'timedOut' { $status = 'TimedOut' }
                'retry' { $status = 'Retry' }
                'failed' { $status = "$Intent failed (exit $($execution.ExitCode))" }
                default {
                    if ($outcome -in 'softReboot', 'hardReboot') {
                        $warnings.Add("$Intent returned $($execution.ExitCode): Intune records a $outcome " +
                            'as pending')
                    }
                    $appDetection = @{ Path = $DetectionPath; Rule = $DetectionRule }
                    $post = Invoke-IslWin32DetectionPass -Phase 'Post' @appDetection @passSplat
                    if ($post.TimedOut) { $status = 'TimedOut' }
                    elseif ($Intent -eq 'Install') {
                        $status = if ($post.Detected) { 'Installed after install' }
                        else { 'Not detected after install' }
                        if (-not $post.Detected) {
                            $warnings.Add("Post-install detection: $($post.Reason). Intune reports 0x87D1041C " +
                                'and retries the install at the next check-in')
                        }
                    }
                    else {
                        # Observed flow (W32-UNINSTALL): detected, uninstall command, detected again, and
                        # "Not installed" once the detection stops saying installed
                        $status = if ($post.Detected) { 'Still detected after uninstall' } else { 'Uninstalled' }
                        if ($post.Detected) {
                            $warnings.Add('Post-uninstall detection still reports installed: Intune keeps ' +
                                'the app as installed and retries the uninstall at the next check-in')
                        }
                    }
                }
            }
        }
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }

    Write-Verbose "Completed $($MyInvocation.MyCommand.Name)"
    [pscustomobject]@{
        PSTypeName    = 'IntuneScriptLab.Win32AppResult'
        Status        = $status
        Intent        = $Intent
        PreDetection  = $pre.Script
        PreRules      = $pre.Rules
        Dependencies  = $dependencies.ToArray()
        Superseded    = $superseded.ToArray()
        Install       = if ($Intent -eq 'Install') { $execution } else { $null }
        Uninstall     = if ($Intent -eq 'Uninstall') { $execution } else { $null }
        PostDetection = if ($post) { $post.Script } else { $null }
        PostRules     = if ($post) { $post.Rules } else { @() }
        Warnings      = $warnings.ToArray()
        Architecture  = $runArchitecture
        Context       = $Context
        RunAs         = $runAs
    }
}
