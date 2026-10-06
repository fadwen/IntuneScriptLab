function Invoke-IntuneRequirementTest {
    <#
    .EXTERNALHELP IntuneScriptLab-Help.xml
    .SYNOPSIS
        Runs a Win32 requirement script like Intune and applies the rule to its output.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.RequirementResult')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName', 'PSPath')]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateSet('String', 'DateTime', 'Integer', 'Float', 'Version', 'Boolean')]
        [string]$OutputType,

        [ValidateSet('Equal', 'NotEqual', 'GreaterThan', 'GreaterThanOrEqual', 'LessThan', 'LessThanOrEqual')]
        [string]$Operator = 'Equal',

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value,

        [ValidateSet('x86', 'x64', 'arm64')]
        [string]$Architecture = 'x64',

        [ValidateSet('User', 'System')]
        [string]$Context = 'User',

        # Run as this account instead of the current user (with -Context User): a scheduled task in
        # the account's own session, the way the agent runs user-context scripts as the signed-in
        # user; needs an elevated session
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential,

        [ValidateRange(1, 86400)]
        [int]$TimeoutSeconds = 300
    )

    process {
        Write-Verbose "Starting $($MyInvocation.MyCommand.Name) for $($PSBoundParameters.Keys -join ', ')"

        $scriptRunSplat = @{
            Path           = $Path
            Architecture   = $Architecture
            Context        = $Context
            Phase          = 'requirement'
            TimeoutSeconds = $TimeoutSeconds
        }
        if ($Credential) {
            if ($Context -eq 'System') {
                throw '-Credential applies to -Context User; System runs as NT AUTHORITY\SYSTEM'
            }
            $scriptRunSplat.Credential = $Credential
        }
        $run = Invoke-IslScriptRun @scriptRunSplat
        $compareSplat = @{
            StdOut     = $run.StdOut
            StdErr     = $run.StdErr
            ExitCode   = $run.ExitCode
            TimedOut   = $run.TimedOut
            OutputType = $OutputType
            Operator   = $Operator
            Value      = $Value
        }
        $verdict = Compare-IslRequirementOutput @compareSplat

        Write-Verbose "Completed $($MyInvocation.MyCommand.Name)"
        [pscustomobject]@{
            PSTypeName   = 'IntuneScriptLab.RequirementResult'
            Applicable   = $verdict.Met
            Reason       = $verdict.Reason
            Output       = $verdict.Output
            ExitCode     = $run.ExitCode
            StdOut       = $run.StdOut
            StdErr       = $run.StdErr
            TimedOut     = $run.TimedOut
            Duration     = $run.Duration
            OutputType   = $OutputType
            Operator     = $Operator
            Value        = $Value
            Architecture = $Architecture
            Context      = $Context
            RunAs        = $run.RunAs
            Host         = $run.Host
            ScriptPath   = $run.ScriptPath
        }
    }
}
