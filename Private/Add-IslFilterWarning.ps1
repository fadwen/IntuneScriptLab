function Add-IslFilterWarning {
    <#
    .SYNOPSIS
    Adds a warning about a clause to an assignment filter parser.

    .DESCRIPTION
    For the assignment filter parser. A warning describes a rule that parses but does not do what
    it seems to: a clause that never matches or matches every device, or a property that is
    deprecated or undocumented. It is added to the parser's Warnings as an
    IntuneScriptLab.FilterWarning, which ConvertFrom-IslFilterRule returns.

    .PARAMETER Parser
    The parser state from New-IslFilterParser.

    .PARAMETER Kind
    What the warning is about: NeverMatches, AlwaysMatches, Deprecated or Undocumented.

    .PARAMETER Message
    The warning's text.

    .EXAMPLE
    Add-IslFilterWarning -Parser $parser -Kind 'Deprecated' -Message 'device.osVersion is deprecated'

    Adds one Deprecated warning to $parser.Warnings.

    .INPUTS
    None.

    .OUTPUTS
    None.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Parser,

        [Parameter(Mandatory)]
        [ValidateSet('NeverMatches', 'AlwaysMatches', 'Deprecated', 'Undocumented')]
        [string]$Kind,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $Parser.Warnings.Add([pscustomobject]@{
            PSTypeName = 'IntuneScriptLab.FilterWarning'; Kind = $Kind; Message = $Message
        })
}
