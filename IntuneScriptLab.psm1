#Requires -Version 5.1

# IntuneScriptLab PowerShell Module
# Static analysis for scripts that the Intune Management Extension will run: remediation
# detection/remediation scripts, platform scripts and Win32 app detection/requirement scripts.
# Every rule is backed by an observation in ..\Validation\Findings.md rather than by the docs.

$ModuleRoot = $PSScriptRoot
Write-Verbose "Initializing IntuneScriptLab module from: $ModuleRoot"

# Import Private functions (helpers first, then the rules that use them)
foreach ($folder in 'Private', 'Private\Rules') {
    $functions = Get-ChildItem -Path "$ModuleRoot\$folder\*.ps1" -ErrorAction SilentlyContinue
    foreach ($function in $functions) {
        Write-Verbose "Loading private function: $($function.Name)"
        . $function.FullName
    }
}

# Import Public functions
$publicFunctions = Get-ChildItem -Path "$ModuleRoot\Public\*.ps1" -ErrorAction SilentlyContinue
foreach ($function in $publicFunctions) {
    Write-Verbose "Loading public function: $($function.Name)"
    . $function.FullName
}

# Rule registry: every Find-* function in Private\Rules is a rule. Test-IntuneScript runs them
# in this order so the output reads from "will it run at all" down to "will it report well".
$script:RuleOrder = @(
    'Find-IslPowerShell7Syntax'
    'Find-IslEncodingIssue'
    'Find-IslInteractiveCall'
    'Find-IslExitCodeIssue'
    'Find-IslOutputIssue'
    'Find-IslContextIssue'
    'Find-IslArchitectureIssue'
    'Find-IslArm64Assumption'
    'Find-IslRebootCommand'
    'Find-IslRelativePath'
    'Find-IslLongSleep'
    'Find-IslSignatureIssue'
    'Find-IslExecutionPolicyCall'
    'Find-IslModuleDependency'
    'Find-IslScriptSize'
)

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
    Remove-Variable -Name RuleOrder -Scope Script -ErrorAction SilentlyContinue
}
