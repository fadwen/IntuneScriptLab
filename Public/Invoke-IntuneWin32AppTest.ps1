function Invoke-IntuneWin32AppTest {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Runs a Win32 app's detect, install or uninstall, detect flow the way the Intune agent does.
    #>
    [CmdletBinding()]
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
    if (-not $Architecture) { $Architecture = Get-IslHostArchitecture }

    if (-not $DetectionPath -and -not $DetectionRule) {
        throw 'Give a detection script (-DetectionPath), detection rules (-DetectionRule), or both'
    }
    $command = if ($Intent -eq 'Install') { $InstallCommand } else { $UninstallCommand }
    if (-not $command) { throw "Intent $Intent needs -${Intent}Command" }
    $null = Resolve-Path -LiteralPath $ContentPath -ErrorAction Stop
    foreach ($related in @($DependsOn) + @($Supersedes)) {
        if (-not $related) { continue }
        if (-not $related.Name) { throw 'Every -DependsOn and -Supersedes entry needs a Name' }
        if (-not $related.DetectionPath -and -not $related.DetectionRule) {
            throw "$($related.Name) needs a DetectionPath, DetectionRule entries, or both"
        }
        if ($related.ContentPath) { $null = Resolve-Path -LiteralPath $related.ContentPath -ErrorAction Stop }
    }

    $warnings = [System.Collections.Generic.List[string]]::new()
    if ($InstallContext -eq 'User') {
        # W32-USER-INSTALL: a device-group assignment never installs a user-context app on either join type
        $warnings.Add('Install behavior User: an assignment to a device group never installs the app. The ' +
            'agent logs "user install context and this is a userless check-in" and reports Not applicable ' +
            '(Applicability 1011); assign the app to users')
    }
    $detectionSplat = @{
        Architecture          = $Architecture
        Context               = $Context
        TimeoutSeconds        = $TimeoutSeconds
        EnforceSignatureCheck = $EnforceSignatureCheck
    }
    if ($Credential) {
        if ($Context -eq 'System') {
            throw '-Credential applies to -Context User; System runs as NT AUTHORITY\SYSTEM'
        }
        $detectionSplat.Credential = $Credential
    }
    $runAs = if ($Credential) { $Credential.UserName }
    elseif ($Context -eq 'System') { 'NT AUTHORITY\SYSTEM' }
    elseif ($env:USERDOMAIN) { "$env:USERDOMAIN\$env:USERNAME" }
    else { [Environment]::UserName }

    # One detection pass for this app or a related one: the script (if any) and every rule; all of
    # them must say installed (W32-MULTI-ONEFALSE, W32-MULTI-BOTHTRUE)
    function Invoke-DetectionPass {
        param([string]$Phase, [string]$Path, [hashtable[]]$Rule, [string]$Label)
        $script = if ($Path) { Invoke-IntuneDetectionTest -Path $Path @detectionSplat } else { $null }
        $rules = @(foreach ($entry in $Rule) { Test-IntuneWin32Rule -Rule $entry -RuleType Detection })
        $unmet = @($rules | Where-Object { -not $_.Met })
        $detected = ($null -eq $script -or $script.Detected) -and $unmet.Count -eq 0
        $timedOut = $null -ne $script -and $script.TimedOut
        foreach ($miss in $unmet) {
            $warnings.Add("$Phase detection rule not met$Label ($($miss.Kind) $($miss.Operation)): " +
                $miss.Reason)
        }
        [pscustomobject]@{
            Detected = $detected
            TimedOut = $timedOut
            Script   = $script
            Rules    = $rules
            Reason   = if ($script -and -not $script.Detected) { $script.Reason }
            elseif ($unmet.Count) { ($unmet | ForEach-Object { $_.Reason }) -join '; ' }
            else { 'Script and rules all report installed' }
        }
    }

    # Runs an install or uninstall command line from a copy of a content folder through the 32-bit
    # cmd.exe, as the agent's own 32-bit process does
    function Invoke-ContentCommand {
        param([string]$Phase, [string]$Content, [string]$CommandLine)
        $source = (Resolve-Path -LiteralPath $Content).ProviderPath
        $hostPattern = '(?i)(^|[\s"])powershell(\.exe)?([\s"]|$)'
        if ($CommandLine -match $hostPattern) {
            $warnings.Add("powershell.exe in the $Phase command runs the 32-bit host (the agent is a 32-bit " +
                'process); HKLM:\SOFTWARE and Program Files are redirected there')
        }
        else {
            # The same host hides inside a batch file the command line names: install.cmd calling
            # powershell.exe runs it 32-bit too, from the agent's 32-bit cmd.exe, without the
            # command line showing it
            $first = if ($CommandLine -match '^\s*"([^"]+)"') { $Matches[1] }
            else { ($CommandLine.Trim() -split '\s+', 2)[0] }
            $batch = if ($first -match '(?i)\.(cmd|bat)$') { Join-Path -Path $source -ChildPath $first }
            else { $null }
            if ($batch -and (Test-Path -LiteralPath $batch -PathType Leaf)) {
                $hit = Select-String -LiteralPath $batch -Pattern $hostPattern | Select-Object -First 1
                if ($hit) {
                    $warnings.Add("powershell.exe in $first (line $($hit.LineNumber)), which the $Phase " +
                        'command runs through the 32-bit cmd.exe, is the 32-bit host (the agent is a 32-bit ' +
                        'process); HKLM:\SOFTWARE and Program Files are redirected there')
                }
            }
        }
        $runId = [guid]::NewGuid().ToString('N')
        # Another account cannot reach the caller's temp folder; its copy lives under ProgramData
        $cache = if ($Credential) {
            Join-Path -Path $env:ProgramData -ChildPath "IntuneScriptLab\Runs\$runId"
        }
        else {
            Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "IntuneScriptLab\$runId"
        }
        $copy = Join-Path -Path $cache -ChildPath 'content'
        $null = New-Item -ItemType Directory -Path $copy -Force
        Copy-Item -Path (Join-Path -Path $source -ChildPath '*') -Destination $copy -Recurse -Force
        if ($Credential) { Grant-IslFolderAccess -Path $cache -Account $Credential.UserName }
        try {
            $cmdFolder = if ([Environment]::Is64BitOperatingSystem) { 'SysWOW64' } else { 'System32' }
            $cmd = Join-Path -Path (Join-Path -Path $env:WINDIR -ChildPath $cmdFolder) -ChildPath 'cmd.exe'
            $processSplat = @{
                FilePath         = $cmd
                Arguments        = "/C `"$CommandLine`""
                WorkingDirectory = $copy
                WorkFolder       = $cache
                Context          = $Context
                TimeoutSeconds   = $InstallTimeoutSeconds
                LauncherBitness  = 'x86'
            }
            if ($Credential) { $processSplat.Credential = $Credential }
            $run = Invoke-IslProcess @processSplat
        }
        finally {
            Remove-Item -LiteralPath $cache -Recurse -Force -ErrorAction SilentlyContinue
        }
        [pscustomobject]@{
            PSTypeName = 'IntuneScriptLab.RunResult'
            Phase      = $Phase
            Command    = $CommandLine
            Context    = $Context
            ExitCode   = $run.ExitCode
            TimedOut   = $run.TimedOut
            StdOut     = $run.StdOut
            StdErr     = $run.StdErr
            Duration   = $run.Duration
        }
    }

    function Get-Outcome {
        param($Run)
        if ($Run.TimedOut) { return 'timedOut' }
        if ($ReturnCodes.ContainsKey($Run.ExitCode)) { $ReturnCodes[$Run.ExitCode] } else { 'failed' }
    }

    function ConvertTo-RelatedResult {
        param([string]$Name, [string]$Relationship, [string]$Status, $Pre, $Install, $Uninstall, $Post)
        [pscustomobject]@{
            PSTypeName    = 'IntuneScriptLab.Win32RelatedResult'
            Name          = $Name
            Relationship  = $Relationship
            Status        = $Status
            PreDetection  = $Pre.Script
            PreRules      = $Pre.Rules
            Install       = $Install
            Uninstall     = $Uninstall
            PostDetection = if ($Post) { $Post.Script } else { $null }
            PostRules     = if ($Post) { $Post.Rules } else { @() }
        }
    }

    $pre = Invoke-DetectionPass -Phase 'Pre' -Path $DetectionPath -Rule $DetectionRule -Label ''
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
            $type = if ($dependency.Type) { "$($dependency.Type)" } else { 'autoInstall' }
            $name = "$($dependency.Name)"
            $detect = @{
                Path = $dependency.DetectionPath; Rule = $dependency.DetectionRule; Label = " for dependency $name"
            }
            $childPre = Invoke-DetectionPass -Phase 'Pre' @detect
            $childInstall = $null
            $childPost = $null
            $childStatus = if ($childPre.TimedOut) { 'TimedOut' }
            elseif ($childPre.Detected) { 'Installed' }
            elseif ($type -ne 'autoInstall') { 'Not detected (detect-only dependency)' }
            elseif (-not $dependency.InstallCommand -or -not $dependency.ContentPath) {
                'Not detected (no InstallCommand or ContentPath)'
            }
            else {
                $childRun = @{
                    Phase = 'install'; Content = $dependency.ContentPath; CommandLine = $dependency.InstallCommand
                }
                $childInstall = Invoke-ContentCommand @childRun
                switch (Get-Outcome -Run $childInstall) {
                    'timedOut' { 'TimedOut' }
                    'retry' { 'Retry' }
                    'failed' { "Install failed (exit $($childInstall.ExitCode))" }
                    default {
                        $childPost = Invoke-DetectionPass -Phase 'Post' @detect
                        if ($childPost.Detected) { 'Installed after install' }
                        else { 'Not detected after install' }
                    }
                }
            }
            $relatedSplat = @{
                Name = $name; Relationship = "dependency ($type)"; Status = $childStatus
                Pre = $childPre; Install = $childInstall; Uninstall = $null; Post = $childPost
            }
            $dependencies.Add((ConvertTo-RelatedResult @relatedSplat))
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
            $type = if ($old.Type) { "$($old.Type)" } else { 'update' }
            $name = "$($old.Name)"
            $detect = @{
                Path = $old.DetectionPath; Rule = $old.DetectionRule; Label = " for superseded app $name"
            }
            $oldPre = Invoke-DetectionPass -Phase 'Pre' @detect
            $oldUninstall = $null
            $oldPost = $null
            $oldStatus = if ($oldPre.TimedOut) { 'TimedOut' }
            elseif (-not $oldPre.Detected) { 'Not installed' }
            elseif ($type -ne 'replace') { 'Installed (left in place by update)' }
            elseif (-not $old.UninstallCommand -or -not $old.ContentPath) {
                'Installed (no UninstallCommand or ContentPath)'
            }
            else {
                $oldRun = @{ Phase = 'uninstall'; Content = $old.ContentPath; CommandLine = $old.UninstallCommand }
                $oldUninstall = Invoke-ContentCommand @oldRun
                switch (Get-Outcome -Run $oldUninstall) {
                    'timedOut' { 'TimedOut' }
                    'retry' { 'Retry' }
                    'failed' { "Uninstall failed (exit $($oldUninstall.ExitCode))" }
                    default {
                        $oldPost = Invoke-DetectionPass -Phase 'Post' @detect
                        if ($oldPost.Detected) { 'Still detected after uninstall' } else { 'Uninstalled' }
                    }
                }
            }
            $relatedSplat = @{
                Name = $name; Relationship = "supersedence ($type)"; Status = $oldStatus
                Pre = $oldPre; Install = $null; Uninstall = $oldUninstall; Post = $oldPost
            }
            $superseded.Add((ConvertTo-RelatedResult @relatedSplat))
            if ($type -eq 'replace' -and $oldStatus -notin 'Uninstalled', 'Not installed') {
                $warnings.Add("Superseded app $name (replace): $oldStatus. The agent removes a replace target " +
                    'before it installs the new app (W32-SUP-OLD-B), so the old app would still be present')
            }
        }
    }

    if (-not $status) {
        $execution = Invoke-ContentCommand -Phase $Intent.ToLower() -Content $ContentPath -CommandLine $command
        $outcome = Get-Outcome -Run $execution
        switch ($outcome) {
            'timedOut' { $status = 'TimedOut' }
            'retry' { $status = 'Retry' }
            'failed' { $status = "$Intent failed (exit $($execution.ExitCode))" }
            default {
                if ($outcome -in 'softReboot', 'hardReboot') {
                    $warnings.Add("$Intent returned $($execution.ExitCode): Intune records a $outcome as pending")
                }
                $post = Invoke-DetectionPass -Phase 'Post' -Path $DetectionPath -Rule $DetectionRule -Label ''
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
        Architecture  = $Architecture
        Context       = $Context
        RunAs         = $runAs
    }
}
