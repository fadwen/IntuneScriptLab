# Rule registry: every Find-* function in Private\Rules is a rule. Test-IntuneScript runs them
# in this order so the output reads from "will it run at all" down to "will it report well".
@{
    RuleOrder = @(
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
}
