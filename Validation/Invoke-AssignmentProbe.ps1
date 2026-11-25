#Requires -Version 7.6
#Requires -Modules Microsoft.Graph.Authentication

<#
    .SYNOPSIS
        Creates the round-9 remediations whose only difference is the assignment, to see which are delivered.

    .DESCRIPTION
        Six remediations with the same detection (exit 1 after a probe record) and remediation
        (exit 0 after a probe record), one per assignment shape:

            ASSIGN-NONE       no assignment at all
            ASSIGN-EXCLONLY   an exclusion of the device group and nothing else
            ASSIGN-INEX       an include and an exclusion of the same device group
            ASSIGN-PAST       run-once schedule two hours in the past, the device group
            ASSIGN-USERGRP    hourly, assigned to a user group (SYSTEM context)
            ASSIGN-PAST2      run-once two hours in the past, assigned to a second device group

        Restart the agent on the test devices afterwards, wait ten minutes and read
        HealthScripts.log ("resolved policy count", "inspect ... schedule", "will try to execute now")
        and the ASSIGN-*.jsonl probe files. Findings.md ("Assignment sanity") holds the outcome.
        Existing policies of the same name are left alone.

    .PARAMETER DeviceGroupName
        The device group the include, exclusion and run-once assignments target.

    .PARAMETER UserGroupName
        The user group ASSIGN-USERGRP targets. One member should be signed in on a test device.

    .PARAMETER SecondDeviceGroupName
        The device group ASSIGN-PAST2 targets: a device whose clock is right, when the first one's is not.

    .EXAMPLE
        Connect-MgGraph -TenantId $tenant -ClientId $app -CertificateThumbprint $thumbprint
        .\Invoke-AssignmentProbe.ps1

        Creates the six policies against the kit's default groups and prints their ids.

    .EXAMPLE
        .\Invoke-AssignmentProbe.ps1 -DeviceGroupName 'Lab-Devices' -UserGroupName 'Lab-Users'

        The same against other groups.

    .EXAMPLE
        .\Invoke-AssignmentProbe.ps1 -WhatIf

        Shows what would be created.

    .INPUTS
        None.

    .OUTPUTS
        System.String. One line per policy.

    .NOTES
        Author: Jeffrey Stuhr. Needs DeviceManagementScripts.ReadWrite.All and Group.Read.All.
        The service keeps only the include when the same group is included and excluded on one
        policy: read /assignments back to see it.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$DeviceGroupName = 'ISL-Validation-Devices',

    [string]$UserGroupName = 'ISL-ESP-Users',

    [string]$SecondDeviceGroupName = 'ISL-ESP-Devices'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$beta = 'https://graph.microsoft.com/beta'
$probe = Get-Content -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath 'Probe.ps1') -Raw


function ConvertTo-Content {
    <#
    .SYNOPSIS
        Builds the base64 content of a probe script that ends with the given statements.

    .DESCRIPTION
        Appends the statements to the text of Probe.ps1, which defines Write-ProbeRecord, with CRLF
        line endings, encodes the result as UTF-8 with a byte order mark, and returns it as base64,
        the form deviceHealthScripts takes for detectionScriptContent and remediationScriptContent.

    .PARAMETER Body
        The statements that follow the probe functions, such as
        'Write-ProbeRecord ASSIGN-NONE detection; exit 1'.

    .EXAMPLE
        ConvertTo-Content -Body 'Write-ProbeRecord ASSIGN-NONE detection; exit 1'

        The base64 content of a detection script that writes a probe record and exits 1.

    .INPUTS
        None.

    .OUTPUTS
        System.String. The script as base64.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$Body
    )

    $text = $probe.TrimEnd() + "`r`n" + $Body + "`r`n"
    $bytes = [Text.UTF8Encoding]::new($true).GetPreamble() + [Text.Encoding]::UTF8.GetBytes($text)
    [Convert]::ToBase64String($bytes)
}


function Get-GroupId {
    <#
    .SYNOPSIS
        Gets the object id of the Microsoft Entra group with the given display name.

    .DESCRIPTION
        Asks Graph for the groups whose display name equals the name and returns the id of the
        first. A name that no group has ends the function with a terminating error.

    .PARAMETER Name
        The display name of the group, such as 'ISL-Validation-Devices'.

    .EXAMPLE
        Get-GroupId -Name 'ISL-Validation-Devices'

        The id of the kit's default device group.

    .INPUTS
        None.

    .OUTPUTS
        System.String. The group's id.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$Name
    )

    $uri = "$beta/groups?`$filter=displayName eq '$Name'&`$select=id"
    try {
        $group = (Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop).value
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }

    if (-not $group) {
        $exception = [System.Management.Automation.ItemNotFoundException]::new("Group not found: $Name")
        $category = [System.Management.Automation.ErrorCategory]::ObjectNotFound
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception, 'GroupNotFound', $category, $Name)
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $group[0].id
}


$devices = Get-GroupId -Name $DeviceGroupName
$users = Get-GroupId -Name $UserGroupName
$second = Get-GroupId -Name $SecondDeviceGroupName
$include = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $devices }
$exclude = @{ '@odata.type' = '#microsoft.graph.exclusionGroupAssignmentTarget'; groupId = $devices }
$userTarget = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $users }
$secondTarget = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $second }
$hourly = @{ '@odata.type' = '#microsoft.graph.deviceHealthScriptHourlySchedule'; interval = 1 }
$past = (Get-Date).ToUniversalTime().AddHours(-2)
$runOncePast = @{
    '@odata.type' = '#microsoft.graph.deviceHealthScriptRunOnceSchedule'; interval = 1; useUtc = $true
    date          = $past.ToString('yyyy-MM-dd'); time = $past.ToString('HH:mm:ss')
}
$experiments = @(
    @{ Name = 'ASSIGN-NONE'; Question = 'A remediation with no assignment: delivered anywhere'; Assignments = @() }
    @{ Name = 'ASSIGN-EXCLONLY'; Question = 'Only an exclusion assignment: delivered anywhere'
        Assignments = @(@{ target = $exclude; runRemediationScript = $true; runSchedule = $hourly }) }
    @{ Name = 'ASSIGN-INEX'; Question = 'Include and exclude of the same device group: delivered'
        Assignments = @(
            @{ target = $include; runRemediationScript = $true; runSchedule = $hourly }
            @{ target = $exclude; runRemediationScript = $true; runSchedule = $hourly }) }
    @{ Name = 'ASSIGN-PAST'; Question = 'Run-once schedule two hours in the past: run at fetch or never'
        Assignments = @(@{ target = $include; runRemediationScript = $true; runSchedule = $runOncePast }) }
    @{ Name = 'ASSIGN-USERGRP'; Question = 'SYSTEM remediation assigned to a user group: runs where a member is'
        Assignments = @(@{ target = $userTarget; runRemediationScript = $true; runSchedule = $hourly }) }
    @{ Name = 'ASSIGN-PAST2'; Question = 'Run-once two hours in the past, on a device with a correct clock'
        Assignments = @(@{ target = $secondTarget; runRemediationScript = $true; runSchedule = $runOncePast }) }
)

$listUri = "$beta/deviceManagement/deviceHealthScripts?`$select=id,displayName"
$existing = @((Invoke-MgGraphRequest -Method GET -Uri $listUri).value)
foreach ($exp in $experiments) {
    $name = "ISL-$($exp.Name)"
    $found = $existing | Where-Object displayName -eq $name
    if ($found) { "exists $name $($found.id)"; continue }
    if (-not $PSCmdlet.ShouldProcess($name, 'Create remediation')) { continue }
    $body = @{
        displayName              = $name; description = $exp.Question; publisher = 'IntuneScriptLab'
        enforceSignatureCheck    = $false; runAs32Bit = $false; runAsAccount = 'system'
        detectionScriptContent   = ConvertTo-Content -Body "Write-ProbeRecord $($exp.Name) detection; exit 1"
        remediationScriptContent = ConvertTo-Content -Body "Write-ProbeRecord $($exp.Name) remediation; exit 0"
    }
    $policy = Invoke-MgGraphRequest -Method POST -Uri "$beta/deviceManagement/deviceHealthScripts" -Body $body
    if ($exp.Assignments.Count) {
        $assignUri = "$beta/deviceManagement/deviceHealthScripts/$($policy.id)/assign"
        $null = Invoke-MgGraphRequest -Method POST -Uri $assignUri -Body @{
            deviceHealthScriptAssignments = $exp.Assignments
        }
    }
    "created $name $($policy.id) assignments=$($exp.Assignments.Count)"
}
"run-once schedules: $($runOncePast.date) $($runOncePast.time) UTC"
