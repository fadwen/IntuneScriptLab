#Requires -Version 5.1

# IntuneScriptLab PowerShell Module
# Static analysis for scripts that the Intune Management Extension will run: remediation
# detection/remediation scripts, platform scripts and Win32 app detection/requirement scripts.
# Every rule is backed by an observation in ..\Validation\Findings.md rather than by the docs.

Set-StrictMode -Version Latest

# Private helpers first, then the rules that use them, then the public functions. A folder that
# is missing or a file that fails to load fails the import: without that the module would import
# with commands missing.
$privateFolder = Join-Path -Path $PSScriptRoot -ChildPath 'Private'
$functionFolders = @(
    $privateFolder
    (Join-Path -Path $privateFolder -ChildPath 'Rules')
    (Join-Path -Path $PSScriptRoot -ChildPath 'Public')
)
foreach ($functionFolder in $functionFolders) {
    if (-not (Test-Path -LiteralPath $functionFolder -PathType Container)) {
        throw "The module folder '$functionFolder' is missing."
    }

    foreach ($functionFile in Get-ChildItem -LiteralPath $functionFolder -Filter '*.ps1' -File) {
        try {
            Write-Verbose "Loading $($functionFile.FullName)"
            . $functionFile.FullName
        } catch {
            # Not dead code: an error in a dot-sourced file, such as one that does not parse, ends
            # only that statement. Rethrown here it ends the root module, and so the import.
            throw
        }
    }
}

# What every internal operation passes to a cmdlet that asks ShouldProcess: a run folder, a copy,
# a work folder, a cleanup. A command that runs a script or writes a report asks its caller once.
# After that neither -WhatIf nor -Confirm, nor a preference in the caller's session, has a say in
# the bookkeeping. With -WhatIf alone pinned, a caller who had said Yes to -Confirm was asked again
# for each of these, and a No to the copy started the host on a file that was not there.
$script:IslInternal = @{ WhatIf = $false; Confirm = $false }

# Static tables live as data under Data (MOD-20), each read once here. A file that is missing or
# does not parse fails the import, as a function file that does not load does.
# RuleOrder: every Find-* function in Private\Rules is a rule, and Test-IntuneScript runs them in
# this order. IslInboxModules, IslWindowsReleaseBuilds and IslAgentLogEventDefinitions are read by
# Get-IslInboxModule, Get-IslWindowsReleaseBuild and Get-IslAgentLogEvent.
$dataFolder = Join-Path -Path $PSScriptRoot -ChildPath 'Data'
$dataFiles = [ordered]@{
    RuleOrder = @('RuleOrder.psd1', 'RuleOrder')
    IslInboxModules = @('InboxModules.psd1', 'Modules')
    IslWindowsReleaseBuilds = @('WindowsReleaseBuilds.psd1', 'Builds')
    IslAgentLogEventDefinitions = @('AgentLogEvents.psd1', 'Definitions')
}
foreach ($entry in $dataFiles.GetEnumerator()) {
    $dataPath = Join-Path -Path $dataFolder -ChildPath $entry.Value[0]
    try {
        $data = Import-PowerShellDataFile -LiteralPath $dataPath -ErrorAction Stop
    } catch {
        # Rethrown, as for a function file: without it Import-Module reports the error and leaves
        # it to the caller to notice that nothing was imported
        throw
    }
    Set-Variable -Name $entry.Key -Scope Script -Value $data[$entry.Value[1]]
}
# The loop's own variables would otherwise stay in the module scope, where a function that reads
# one of these names without assigning it would find them
Remove-Variable -Name dataFolder, dataFiles, entry, dataPath, data

# Pester assertions: approved-verb functions, exported under the Should-* names Pester users
# expect (aliases are not verb-checked, so Import-Module stays warning-free)
Set-Alias -Name Should-HaveIntuneStatus -Value Assert-HaveIntuneStatus
Set-Alias -Name Should-BeIntuneDetected -Value Assert-BeIntuneDetected
Set-Alias -Name Should-NotBeIntuneDetected -Value Assert-NotBeIntuneDetected
Set-Alias -Name Should-HaveIntuneRunState -Value Assert-HaveIntuneRunState
Set-Alias -Name Should-PassIntuneAnalysis -Value Assert-PassIntuneAnalysis
Set-Alias -Name Should-BeIntuneApplicable -Value Assert-BeIntuneApplicable
Set-Alias -Name Should-NotBeIntuneApplicable -Value Assert-NotBeIntuneApplicable

Export-ModuleMember -Function @(
    'Test-IntuneScript'
    'Invoke-IntuneDetectionTest'
    'Invoke-IntuneRemediationTest'
    'Invoke-IntunePlatformScriptTest'
    'Invoke-IntuneWin32AppTest'
    'Invoke-IntuneRequirementTest'
    'Test-IntuneWin32Rule'
    'Test-IntuneWin32Requirement'
    'Get-IntuneAgentLog'
    'Get-IntuneAgentTimeline'
    'Export-IntuneAgentDiagnostic'
    'Get-IntuneAnalyzerRulePath'
    'Test-IntuneDeployedScript'
    'Compare-IntuneDeployedScript'
    'Get-IntuneScriptHealth'
    'Export-IntuneFindingSarif'
    'Repair-IntuneScript'
    'Test-IntuneAssignmentFilter'
    'Assert-HaveIntuneStatus'
    'Assert-BeIntuneDetected'
    'Assert-NotBeIntuneDetected'
    'Assert-HaveIntuneRunState'
    'Assert-PassIntuneAnalysis'
    'Assert-BeIntuneApplicable'
    'Assert-NotBeIntuneApplicable'
) -Alias @(
    'Should-HaveIntuneStatus'
    'Should-BeIntuneDetected'
    'Should-NotBeIntuneDetected'
    'Should-HaveIntuneRunState'
    'Should-PassIntuneAnalysis'
    'Should-BeIntuneApplicable'
    'Should-NotBeIntuneApplicable'
)

$ExecutionContext.SessionState.Module.OnRemove = {
    Write-Verbose 'Cleaning up IntuneScriptLab module'
    $tables = 'RuleOrder', 'IslInboxModules', 'IslWindowsReleaseBuilds', 'IslAgentLogEventDefinitions'
    Remove-Variable -Name $tables -Scope Script -ErrorAction SilentlyContinue
}
