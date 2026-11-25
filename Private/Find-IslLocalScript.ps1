function Find-IslLocalScript {
    <#
    .SYNOPSIS
    Finds the local files that may hold one script of a tenant policy.

    .DESCRIPTION
    For Compare-IntuneDeployedScript. When -Map has an entry for the policy (Get-IslMapEntry),
    the entry names the file: a path for the detection or platform script, or a hashtable of
    paths by role. A relative path is under the root. A role the entry leaves out has no file.

    Otherwise the names decide, matched by ConvertTo-IslNameKey. With a pattern, the candidates
    are the scripts in a folder named after the policy whose base names match it, such as
    ^(?i)detect. Without one, they are the scripts named after the policy, and the single script
    in a folder named after it.

    .PARAMETER Policy
    The policy as Graph returns it, with displayName and id.

    .PARAMETER Role
    The script's role: detection, remediation, script or requirement.

    .PARAMETER Pattern
    A regular expression the base names in the policy's folder must match. Leave it out for a
    policy with one script.

    .PARAMETER Root
    The full path of the caller's -Path.

    .PARAMETER LocalFile
    Every .ps1 file under the root.

    .PARAMETER LocalFolder
    The root and every folder under it.

    .PARAMETER Map
    The caller's -Map. Nothing makes the names decide.

    .PARAMETER Matched
    The -Map keys matched so far, which Get-IslMapEntry adds to.

    .EXAMPLE
    Find-IslLocalScript -Policy $policy -Role 'detection' -Pattern '^(?i)detect' @localOptions
    # $localOptions holds Root, LocalFile, LocalFolder, Map and Matched

    The detection script in the folder named after the remediation.

    .INPUTS
    None.

    .OUTPUTS
    System.Object. Each candidate, an object with FullName.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Policy,

        [Parameter(Mandatory)]
        [string]$Role,

        [Parameter()]
        [string]$Pattern,

        [Parameter(Mandatory)]
        [string]$Root,

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$LocalFile = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$LocalFolder = @(),

        [Parameter()]
        [AllowNull()]
        [hashtable]$Map,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [hashtable]$Matched
    )

    $entry = Get-IslMapEntry -Policy $Policy -Map $Map -Matched $Matched
    if ($null -ne $entry) {
        $value = $null
        if ($entry -is [hashtable]) {
            $roleKey = @($entry.Keys | Where-Object { "$_" -eq $Role })
            if ($roleKey.Count) { $value = $entry[$roleKey[0]] }
        } elseif ($Role -in 'detection', 'script') {
            $value = $entry
        }
        if ($null -eq $value -or "$value" -eq '') { return }
        $full = if ([System.IO.Path]::IsPathRooted("$value")) {
            "$value"
        } else {
            Join-Path -Path $Root -ChildPath "$value"
        }
        return [pscustomobject]@{ FullName = $full }
    }
    $key = ConvertTo-IslNameKey -Value "$(Get-IslPropertyValue -InputObject $Policy -Name 'displayName')"
    $named = @($LocalFolder | Where-Object { (ConvertTo-IslNameKey -Value $_.Name) -eq $key })
    $inside = @(foreach ($folder in $named) {
            $LocalFile | Where-Object { $_.DirectoryName -eq $folder.FullName }
        })
    if ($Pattern) { return $inside | Where-Object { $_.BaseName -match $Pattern } }
    $byName = @($LocalFile | Where-Object { (ConvertTo-IslNameKey -Value $_.BaseName) -eq $key })
    $single = @(if ($inside.Count -eq 1) { $inside })
    $byName + $single | Sort-Object -Property FullName -Unique
}
