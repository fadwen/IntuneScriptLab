function Get-IslCredentialArgument {
    <#
    .SYNOPSIS
    Gets what a Get-Credential call is handed as its credential.

    .DESCRIPTION
    For the interactive-call rule: Get-Credential -Credential returns a credential that is already
    built, and prompts only for the password of a user name. This gives the argument of
    -Credential, named by any prefix of the name, or the first positional argument, which binds to
    -Credential. It gives nothing when the call names -Message, -UserName or -Title, which always
    prompt, or has no such argument. A value right after another parameter belongs to that
    parameter and is passed over.

    .PARAMETER Command
    The Get-Credential call.

    .EXAMPLE
    Get-IslCredentialArgument -Command $command

    The syntax tree of $credential for Get-Credential -Credential $credential.

    .INPUTS
    None.

    .OUTPUTS
    System.Management.Automation.Language.Ast. The argument, or nothing.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.Language.Ast])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.CommandAst]$Command
    )

    foreach ($prompting in 'Message', 'UserName', 'Title') {
        if (Test-IslCommandParameter -Command $Command -ParameterName $prompting) { return }
    }
    $elements = @($Command.CommandElements | Select-Object -Skip 1)
    for ($index = 0; $index -lt $elements.Count; $index++) {
        $element = $elements[$index]
        if ($element.GetType().Name -eq 'CommandParameterAst') {
            if (-not 'Credential'.StartsWith($element.ParameterName, 'OrdinalIgnoreCase')) { continue }
            if ($element.Argument) { return $element.Argument }
            if ($index + 1 -lt $elements.Count) { return $elements[$index + 1] }
            return
        }
        # A value right after another parameter belongs to that parameter
        $previous = if ($index -gt 0) { $elements[$index - 1] } else { $null }
        $taken = $previous -and $previous.GetType().Name -eq 'CommandParameterAst' -and -not $previous.Argument
        if (-not $taken) { return $element }
    }
}
