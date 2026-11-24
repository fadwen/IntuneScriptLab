function ConvertTo-IslWin32RelatedResult {
    <#
    .SYNOPSIS
    Builds the result of a dependency or a superseded app in a Win32 app flow.

    .DESCRIPTION
    For Invoke-IntuneWin32AppTest, which lists these under Dependencies and Superseded. The
    detections are given as the passes Invoke-IslWin32DetectionPass returns, and the result
    carries their script results and rules; a pass that did not happen leaves its fields empty.

    .PARAMETER Name
    The name of the related app.

    .PARAMETER Relationship
    How it relates to the app, such as "dependency (autoInstall)" or "supersedence (replace)".

    .PARAMETER Status
    What the flow came to for it, such as Installed after install or Uninstalled.

    .PARAMETER Pre
    The detection pass before anything ran.

    .PARAMETER Install
    The install run, when there was one.

    .PARAMETER Uninstall
    The uninstall run, when there was one.

    .PARAMETER Post
    The detection pass after the install or uninstall, when there was one.

    .EXAMPLE
    $relatedSplat = @{ Name = 'Runtime'; Relationship = 'dependency (autoInstall)'; Status = 'Installed' }
    ConvertTo-IslWin32RelatedResult @relatedSplat -Pre $childPre

    A dependency that was already installed.

    .INPUTS
    None.

    .OUTPUTS
    IntuneScriptLab.Win32RelatedResult. Name, Relationship, Status, PreDetection, PreRules,
    Install, Uninstall, PostDetection and PostRules.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.Win32RelatedResult')]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Relationship,

        [Parameter(Mandatory)]
        [string]$Status,

        [Parameter(Mandatory)]
        [psobject]$Pre,

        [Parameter()]
        [AllowNull()]
        [psobject]$Install,

        [Parameter()]
        [AllowNull()]
        [psobject]$Uninstall,

        [Parameter()]
        [AllowNull()]
        [psobject]$Post
    )

    [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.Win32RelatedResult'
        Name = $Name
        Relationship = $Relationship
        Status = $Status
        PreDetection = $Pre.Script
        PreRules = $Pre.Rules
        Install = $Install
        Uninstall = $Uninstall
        PostDetection = if ($Post) { $Post.Script } else { $null }
        PostRules = if ($Post) { $Post.Rules } else { @() }
    }
}
