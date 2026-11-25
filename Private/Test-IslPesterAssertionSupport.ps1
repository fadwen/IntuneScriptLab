# The module's Pester 6.2+ assertions, the Assert-* commands in Public, are built on
# New-ShouldAssertion in the shape the repository's custom-assertion guide prescribes, and exported
# under Should-* aliases (Set-Alias in the module file). Each fails with the diagnosis Intune would give.
function Test-IslPesterAssertionSupport {
    <#
    .SYNOPSIS
        Ends with an error when the Pester that is loaded cannot carry the assertions.

    .DESCRIPTION
        New-ShouldAssertion arrived in Pester 6.2; without it the module's Assert- commands
        cannot report a failure properly. Returns nothing when the command is there.

    .EXAMPLE
        Test-IslPesterAssertionSupport

        Nothing with Pester 6.2 or later loaded, and a terminating error otherwise.

    .INPUTS
        None.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if (-not (Get-Command -Name New-ShouldAssertion -ErrorAction SilentlyContinue)) {
        $recordSplat = @{
            Message = 'The IntuneScriptLab assertions need Pester 6.2 or later loaded (Import-Module Pester)'
            ErrorId = 'PesterAssertionNotSupported'
            Category = [System.Management.Automation.ErrorCategory]::NotInstalled
            TargetObject = 'Pester'
        }
        $PSCmdlet.ThrowTerminatingError((New-IslErrorRecord @recordSplat))
    }
}
