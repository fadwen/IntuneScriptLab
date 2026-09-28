#Requires -Version 7.4
#Requires -Modules Microsoft.Graph.Authentication

<#
    .SYNOPSIS
        Records what the service accepts, refuses and matches in assignment filter rules.

    .DESCRIPTION
        Two matrices against the tenant, nothing created:

        - Syntax (FLT-V*, FLT-W*, FLT-X*): each rule is sent to
          deviceManagement/assignmentFilters/validateFilter for the Windows 10 and later platform
          and the isValidRule answer is recorded.
        - Matching (FLT-E*, FLT-F*, FLT-Y*): each rule is sent to
          deviceManagement/evaluateAssignmentFilter, the call behind the portal's Preview devices,
          and the device names it returns are recorded. Rules are written against one enrolled
          device's own values (name, model, manufacturer, OS version, SKU), so the matrix reads
          the same on any tenant.

        The results feed Findings.md ("Assignment filter rules") and the tests of
        ConvertFrom-IslFilterRule and Test-IntuneAssignmentFilter, which encode the same rules.

    .PARAMETER DeviceName
        The managed device whose values the matching rules are written against. Default: the first
        Microsoft Entra joined device in the tenant.

    .PARAMETER OutputPath
        Where the JSON of both matrices is written. Default: Results\filter-probe.json next to this
        script (Results is gitignored).

    .EXAMPLE
        Connect-MgGraph -TenantId $tenant -ClientId $app -CertificateThumbprint $thumbprint
        .\Invoke-FilterProbe.ps1

        Prints one line per rule and writes Results\filter-probe.json.

    .EXAMPLE
        .\Invoke-FilterProbe.ps1 -DeviceName LAB-042 -OutputPath C:\Temp\filters.json

        The matching matrix against LAB-042 instead of the first joined device.

    .EXAMPLE
        $probe = Get-Content .\Results\filter-probe.json | ConvertFrom-Json
        $probe.Syntax | Where-Object Valid -eq $false | Select-Object Id, Rule

        The rules the service refused in the last run.

    .INPUTS
        None.

    .OUTPUTS
        None. Progress lines on the host, JSON at -OutputPath.

    .NOTES
        Author: Jeffrey Stuhr. Needs DeviceManagementConfiguration.ReadWrite.All (validateFilter is
        an action on the filters collection) and DeviceManagementManagedDevices.Read.All.
        evaluateAssignmentFilter answers with an octet stream, so it is read through a file.
#>
[CmdletBinding()]
param(
    [string]$DeviceName,

    [string]$OutputPath = (Join-Path $PSScriptRoot 'Results\filter-probe.json')
)

$ErrorActionPreference = 'Stop'
if (-not (Get-MgContext)) { throw 'Connect-MgGraph first; this script uses the current session' }
$graph = 'https://graph.microsoft.com/beta'

# The device the matching rules are written against
$deviceSelect = 'id,deviceName,manufacturer,model,osVersion,skuNumber,joinType,managedDeviceOwnerType'
$deviceUri = "$graph/deviceManagement/managedDevices?`$select=$deviceSelect"
$devices = @((Invoke-MgGraphRequest -Method GET -Uri $deviceUri).value)
$device = if ($DeviceName) { $devices | Where-Object deviceName -eq $DeviceName | Select-Object -First 1 }
else { $devices | Where-Object joinType -eq 'azureADJoined' | Select-Object -First 1 }
if (-not $device) { throw "No managed device found ($DeviceName)" }
$name = $device.deviceName
$osVersion = $device.osVersion
$osShort = ($osVersion -split '\.')[0..2] -join '.'
"Device: $name $($device.manufacturer)/$($device.model) os=$osVersion sku=$($device.skuNumber) " +
    "join=$($device.joinType)"

$syntax = @(
    @{ Id = 'FLT-V01'; Rule = '(device.deviceName -eq "X")' }
    @{ Id = 'FLT-V02'; Rule = '(device.deviceName -notStartsWith "X")' }
    @{ Id = 'FLT-V03'; Rule = '(device.deviceName -endsWith "X")' }
    @{ Id = 'FLT-V04'; Rule = '(device.deviceName -notEndsWith "X")' }
    @{ Id = 'FLT-V05'; Rule = 'not (device.deviceName -eq "X")' }
    @{ Id = 'FLT-V06'; Rule = '-not (device.deviceName -eq "X")' }
    @{ Id = 'FLT-V07'; Rule = '!(device.deviceName -eq "X")' }
    @{ Id = 'FLT-V08'; Rule = '(device.deviceName eq "X")' }
    @{ Id = 'FLT-V09'; Rule = '(device.deviceName -EQ "X")' }
    @{ Id = 'FLT-V10'; Rule = '(device.DEVICENAME -eq "X")' }
    @{ Id = 'FLT-V11'; Rule = '(DEVICE.deviceName -eq "X")' }
    @{ Id = 'FLT-V12'; Rule = "(device.deviceName -eq 'X')" }
    @{ Id = 'FLT-V13'; Rule = '(device.deviceName -eq X)' }
    @{ Id = 'FLT-V14'; Rule = 'device.deviceName -eq "X"' }
    @{ Id = 'FLT-V15'; Rule = '(device.deviceName -eq "A") AND (device.model -eq "B")' }
    @{ Id = 'FLT-V16'; Rule = '(device.deviceName -eq "A") -and (device.model -eq "B")' }
    @{ Id = 'FLT-V17'; Rule = '(device.deviceName -eq "A") -or (device.model -eq "B")' }
    @{ Id = 'FLT-V18'; Rule = '(device.deviceName -in "X")' }
    @{ Id = 'FLT-V19'; Rule = '(device.deviceName -in ["X"])' }
    @{ Id = 'FLT-V20'; Rule = '(device.deviceName -gt "X")' }
    @{ Id = 'FLT-V21'; Rule = '(device.operatingSystemVersion -gt 10.0.22000.1000)' }
    @{ Id = 'FLT-V22'; Rule = '(device.operatingSystemVersion -gt "10.0.22000.1000")' }
    @{ Id = 'FLT-V23'; Rule = '(device.operatingSystemVersion -startsWith "10.0")' }
    @{ Id = 'FLT-V24'; Rule = '(device.osVersion -gt "10.0")' }
    @{ Id = 'FLT-V25'; Rule = '(device.cpuArchitecture -eq "x64")' }
    @{ Id = 'FLT-V26'; Rule = '(device.cpuArchitecture -contains "arm")' }
    @{ Id = 'FLT-V27'; Rule = '(device.deviceTrustType -eq "Microsoft Entra joined")' }
    @{ Id = 'FLT-V28'; Rule = '(device.enrollmentProfileName -ne $null)' }
    @{ Id = 'FLT-V29'; Rule = '(device.enrollmentProfileName -eq null)' }
    @{ Id = 'FLT-V30'; Rule = '(device.enrollmentProfileName -eq "null")' }
    @{ Id = 'FLT-V31'; Rule = '(device.deviceName -startsWith $null)' }
    @{ Id = 'FLT-V32'; Rule = '(device.noSuchProperty -eq "X")' }
    @{ Id = 'FLT-V33'; Rule = '(app.deviceModel -eq "X")' }
    @{ Id = 'FLT-V34'; Rule = '((device.deviceName -eq "A") or (device.deviceName -eq "B")) and ' +
        '(device.model -eq "C")' }
    @{ Id = 'FLT-V35'; Rule = "(device.deviceName`n  -eq   `"X`" )`n" }
    @{ Id = 'FLT-V36'; Rule = '(device.deviceName -contains "")' }
    @{ Id = 'FLT-V37'; Rule = '(device.isRooted -eq "True")' }
    @{ Id = 'FLT-V38'; Rule = '(device.deviceOwnership -eq "Personal")' }
    @{ Id = 'FLT-V39'; Rule = '(device.deviceOwnership -startsWith "Pers")' }
    @{ Id = 'FLT-V40'; Rule = '(device.operatingSystemSKU -eq "Enterprise")' }
    @{ Id = 'FLT-V41'; Rule = '(device.deviceName -eq "X") (device.model -eq "Y")' }
    @{ Id = 'FLT-V42'; Rule = '(device.deviceName -eq "X") or' }
    @{ Id = 'FLT-V43'; Rule = '(device.deviceName -eq "It''s")' }
    @{ Id = 'FLT-V44'; Rule = '(device.deviceName -eq "say \"hi\"")' }
    @{ Id = 'FLT-V45'; Rule = '(device.deviceName -eq "say ""hi""")' }
    @{ Id = 'FLT-V46'; Rule = '(device.deviceName -in ["A", "B",])' }
    @{ Id = 'FLT-V47'; Rule = '(device.operatingSystemVersion -eq 10)' }
    @{ Id = 'FLT-V48'; Rule = '(device.operatingSystemVersion -gt 10.0.22000.1000.5)' }
    @{ Id = 'FLT-V49'; Rule = '(device.deviceName -equals "X")' }
    @{ Id = 'FLT-V50'; Rule = '(device.deviceName -eq "X") xor (device.model -eq "Y")' }
    @{ Id = 'FLT-V51'; Rule = '' }
    @{ Id = 'FLT-V52'; Rule = '(device.deviceName -ne $null)' }
    @{ Id = 'FLT-V53'; Rule = '(device.deviceName -in [])' }
    @{ Id = 'FLT-V54'; Rule = '(device.deviceName -notIn ["A"])' }
    @{ Id = 'FLT-V55'; Rule = '(device.deviceName -notContains "A")' }
    @{ Id = 'FLT-V56'; Rule = '(device.operatingSystemVersion -in ["10.0.22000.1000"])' }
    @{ Id = 'FLT-V57'; Rule = '(device.deviceName -eq "A") and (device.deviceName -eq "B") or ' +
        '(device.deviceName -eq "C")' }
    @{ Id = 'FLT-V58'; Rule = '(device.deviceName -eq 42)' }
    @{ Id = 'FLT-V59'; Rule = '(device.model -Contains "X")' }
    @{ Id = 'FLT-V60'; Rule = '(device.deviceManagementType -eq "Corporate-owned fully managed")' }
    @{ Id = 'FLT-V61'; Rule = '(device.cpuArchitecture -startsWith "arm")' }
    @{ Id = 'FLT-V62'; Rule = '(device.deviceTrustType -contains "joined")' }
    @{ Id = 'FLT-V63'; Rule = '(device.osVersion -eq $null)' }
    @{ Id = 'FLT-V64'; Rule = '(device.operatingSystemVersion -eq $null)' }
    @{ Id = 'FLT-W01'; Rule = '(device.operatingSystemVersion -eq 10.0)' }
    @{ Id = 'FLT-W02'; Rule = '(device.operatingSystemVersion -eq 10.0.26100)' }
    @{ Id = 'FLT-W03'; Rule = '(device.deviceName -eq "")' }
    @{ Id = 'FLT-W04'; Rule = '(device.deviceName -ne "")' }
    @{ Id = 'FLT-W05'; Rule = '(device.deviceName -startsWith "")' }
    @{ Id = 'FLT-W06'; Rule = '(device.deviceName -in [""])' }
    @{ Id = 'FLT-W07'; Rule = '(device.deviceName -eq "X"))' }
    @{ Id = 'FLT-W08'; Rule = '((device.deviceName -eq "X")' }
    @{ Id = 'FLT-W09'; Rule = '(device.deviceName -eq "X") or ()' }
    @{ Id = 'FLT-W10'; Rule = 'device.deviceName -eq "A" and device.model -eq "B"' }
    @{ Id = 'FLT-W11'; Rule = '(device.deviceName -eq "A" and device.model -eq "B")' }
    @{ Id = 'FLT-W12'; Rule = '((device.deviceName -eq "A"))' }
    @{ Id = 'FLT-W13'; Rule = '(device.deviceName-eq"X")' }
    @{ Id = 'FLT-W14'; Rule = '(device.deviceName -eq "X"' }
    @{ Id = 'FLT-W15'; Rule = '(device.enrollmentProfileName -in [$null])' }
    @{ Id = 'FLT-W16'; Rule = '(device.deviceName -notIn ["A", $null])' }
    @{ Id = 'FLT-W17'; Rule = '(device.operatingSystemVersion -ge "10.0.26100")' }
    @{ Id = 'FLT-W18'; Rule = '(device.osVersion -in "10.0")' }
    @{ Id = 'FLT-W19'; Rule = '(device.deviceName -IN ["X"]) OR (device.deviceName -NOTIN ["Y"])' }
    @{ Id = 'FLT-W20'; Rule = '(device.deviceName -eq "ab" "cd")' }
    @{ Id = 'FLT-W21'; Rule = '(device.deviceTrustType -eq "Unknown")' }
    @{ Id = 'FLT-W22'; Rule = '(device.cpuArchitecture -eq "Unknown")' }
    @{ Id = 'FLT-W23'; Rule = '(device.deviceOwnership -eq "Unknown")' }
    @{ Id = 'FLT-W24'; Rule = '(device.isTpmAttested -eq "True")' }
    @{ Id = 'FLT-W25'; Rule = '(device.deviceId -eq "X")' }
    @{ Id = 'FLT-W26'; Rule = '(device.userPrincipalName -eq "X")' }
    @{ Id = 'FLT-W27'; Rule = '(device.deviceName -contains " ")' }
    @{ Id = 'FLT-W28'; Rule = '(device.deviceName -eq "X") and' }
    @{ Id = 'FLT-W29'; Rule = '(device.deviceName -eq "X") -AND (device.model -eq "Y")' }
    @{ Id = 'FLT-W30'; Rule = '(device.operatingSystemVersion -gt 10.0.22000.1000) or ' +
        '(device.operatingSystemSKU -in ["Enterprise"])' }
    @{ Id = 'FLT-W31'; Rule = '(device.deviceTrustType -eq $null)' }
    @{ Id = 'FLT-W32'; Rule = '(device.cpuArchitecture -eq $null)' }
    @{ Id = 'FLT-W33'; Rule = '(device.operatingSystemVersion -gt 10.0.22000.1000 )' }
    @{ Id = 'FLT-W34'; Rule = '(device.operatingSystemVersion -gt 10.0.99999999.1)' }
    @{ Id = 'FLT-W35'; Rule = '(device.operatingSystemVersion -gt 10.0.100000000.1)' }
    @{ Id = 'FLT-W36'; Rule = '(device.deviceName -eq "a\b")' }
    @{ Id = 'FLT-W37'; Rule = "(device.deviceName -eq `"tab`ttab`")" }
    @{ Id = 'FLT-W38'; Rule = '(device.deviceName -eq "X") // comment' }
    @{ Id = 'FLT-W39'; Rule = "(device.model -eq `"$($device.model)`")" }
    @{ Id = 'FLT-W40'; Rule = '(device.enrollmentProfileName -contains $null)' }
    @{ Id = 'FLT-X01'; Rule = '(device.deviceName -eq ["A","B"])' }
    @{ Id = 'FLT-X02'; Rule = '(device.deviceName -ne ["A","B"])' }
    @{ Id = 'FLT-X03'; Rule = '(device.deviceOwnership -in ["Personal"])' }
    @{ Id = 'FLT-X04'; Rule = '(device.isTpmAttested -ne "True")' }
    @{ Id = 'FLT-X05'; Rule = '(device.deviceName -startsWith ["A"])' }
    @{ Id = 'FLT-X06'; Rule = '(device.operatingSystemVersion -eq [10.0])' }
    @{ Id = 'FLT-X07'; Rule = '(device.deviceTrustType -eq "Azure AD joined") and' }
    @{ Id = 'FLT-X08'; Rule = '(device.deviceName -eq "X") and (device.deviceName -eq "Y") and ' +
        '(device.deviceName -eq "Z")' }
    @{ Id = 'FLT-X09'; Rule = '(device.deviceName -in ["A"] )' }
    @{ Id = 'FLT-X10'; Rule = '(device.manufacturer -eq "Microsoft Corporation")' }
)

# {name}, {name.lower}, {os}, {os3}, {model}, {model.lower}, {manufacturer.lower} stand for the device's values
$matching = @(
    @{ Id = 'FLT-E01'; Rule = '(device.deviceName -eq "{name.lower}")' }
    @{ Id = 'FLT-E02'; Rule = '(device.deviceName -contains "{name.mid.lower}")' }
    @{ Id = 'FLT-E03'; Rule = '(device.deviceName -startsWith "{name.head}")' }
    @{ Id = 'FLT-E04'; Rule = '(device.deviceName -in ["{name}","nope"])' }
    @{ Id = 'FLT-E05'; Rule = '(device.deviceName -notIn ["{name}"])' }
    @{ Id = 'FLT-E06'; Rule = '(device.cpuArchitecture -eq "amd64")' }
    @{ Id = 'FLT-E07'; Rule = '(device.cpuArchitecture -eq "x64")' }
    @{ Id = 'FLT-E08'; Rule = '(device.deviceTrustType -eq "Azure AD joined")' }
    @{ Id = 'FLT-E09'; Rule = '(device.deviceTrustType -eq "Azure AD registered")' }
    @{ Id = 'FLT-E10'; Rule = '(device.deviceTrustType -in ["Hybrid Azure AD joined","Azure AD joined"])' }
    @{ Id = 'FLT-E11'; Rule = '(device.operatingSystemVersion -gt 10.0.22000.1000)' }
    @{ Id = 'FLT-E12'; Rule = '(device.operatingSystemVersion -eq {os})' }
    @{ Id = 'FLT-E13'; Rule = '(device.operatingSystemVersion -ge {os3})' }
    @{ Id = 'FLT-E14'; Rule = '(device.osVersion -startsWith "{os3}")' }
    @{ Id = 'FLT-E15'; Rule = '(device.osVersion -eq "{os}")' }
    @{ Id = 'FLT-E16'; Rule = '(device.manufacturer -eq "{manufacturer.lower}")' }
    @{ Id = 'FLT-E17'; Rule = '(device.model -eq "{model.lower}")' }
    @{ Id = 'FLT-E18'; Rule = '(device.model -contains "{model.head.upper}")' }
    @{ Id = 'FLT-E19'; Rule = '(device.operatingSystemSKU -eq "Enterprise")' }
    @{ Id = 'FLT-E21'; Rule = '(device.enrollmentProfileName -eq $null)' }
    @{ Id = 'FLT-E22'; Rule = '(device.enrollmentProfileName -ne $null)' }
    @{ Id = 'FLT-E23'; Rule = '(device.deviceOwnership -eq "Corporate")' }
    @{ Id = 'FLT-E24'; Rule = '(device.deviceOwnership -eq "Personal")' }
    @{ Id = 'FLT-E25'; Rule = '(device.deviceCategory -eq $null)' }
    @{ Id = 'FLT-E26'; Rule = '(device.deviceCategory -eq "Unknown")' }
    @{ Id = 'FLT-E27'; Rule = '(device.deviceName -eq "{name}") or (device.deviceName -eq "nope") and ' +
        '(device.deviceName -eq "nope")' }
    @{ Id = 'FLT-E28'; Rule = '(device.deviceName -eq "nope") and (device.deviceName -eq "nope") or ' +
        '(device.deviceName -eq "{name}")' }
    @{ Id = 'FLT-E29'; Rule = '(device.deviceName -contains "")' }
    @{ Id = 'FLT-E30'; Rule = '(device.deviceName -eq "{name} ")' }
    @{ Id = 'FLT-E31'; Rule = '(device.deviceName -eq " {name}")' }
    @{ Id = 'FLT-E32'; Rule = '(device.deviceName -notContains "ZZZQ")' }
    @{ Id = 'FLT-E33'; Rule = '(device.deviceName -startsWith "{name.offset}")' }
    @{ Id = 'FLT-E34'; Rule = '(device.deviceName -ne "{name}")' }
    @{ Id = 'FLT-E35'; Rule = '(device.deviceName -ne $null)' }
    @{ Id = 'FLT-E36'; Rule = '(device.osVersion -in ["{os}", "1.0"])' }
    @{ Id = 'FLT-E37'; Rule = '(device.operatingSystemVersion -lt {os})' }
    @{ Id = 'FLT-E38'; Rule = '(device.operatingSystemVersion -ne {os})' }
    @{ Id = 'FLT-E39'; Rule = '(device.deviceName -in ["{name.lower}"])' }
    @{ Id = 'FLT-E40'; Rule = '(device.osVersion -eq "{os3}")' }
    @{ Id = 'FLT-E41'; Rule = '(device.operatingSystemVersion -eq "{os}")' }
    @{ Id = 'FLT-E42'; Rule = '(device.operatingSystemVersion -gt {os3}.0)' }
    @{ Id = 'FLT-E43'; Rule = '(device.deviceTrustType -eq "AzureADJoined")' }
    @{ Id = 'FLT-E44'; Rule = '(device.deviceOwnership -eq "company")' }
    @{ Id = 'FLT-F01'; Rule = '(device.deviceTrustType -eq "Microsoft Entra joined")' }
    @{ Id = 'FLT-F02'; Rule = '(device.deviceName -in "{name}")' }
    @{ Id = 'FLT-F03'; Rule = '(device.operatingSystemVersion -eq {os3})' }
    @{ Id = 'FLT-F04'; Rule = '(device.osVersion -contains "{os.build}")' }
    @{ Id = 'FLT-F05'; Rule = '(device.manufacturer -in ["{manufacturer.lower}"])' }
    @{ Id = 'FLT-F07'; Rule = '(device.deviceName -eq "{name}") and ' +
        '(device.deviceTrustType -eq "Azure AD registered")' }
    @{ Id = 'FLT-F08'; Rule = '((device.deviceName -eq "nope") or (device.deviceName -eq "{name}")) and ' +
        '(device.deviceTrustType -eq "Azure AD registered")' }
    @{ Id = 'FLT-F09'; Rule = '(device.deviceName -eq "nope") or (device.deviceName -eq "{name}") and ' +
        '(device.deviceTrustType -eq "Azure AD registered")' }
    @{ Id = 'FLT-F11'; Rule = '(device.deviceName -startsWith " {name.head}")' }
    @{ Id = 'FLT-F13'; Rule = '(device.operatingSystemSKU -eq "EnterpriseSEval")' }
    @{ Id = 'FLT-F14'; Rule = '(device.operatingSystemSKU -startsWith "enterprise")' }
    @{ Id = 'FLT-F15'; Rule = '(device.operatingSystemSKU -in ["Enterprise","EnterpriseSEval"])' }
    @{ Id = 'FLT-F16'; Rule = '(device.cpuArchitecture -in ["amd64","arm64"])' }
    @{ Id = 'FLT-F17'; Rule = '(device.deviceCategory -ne $null)' }
    @{ Id = 'FLT-F18'; Rule = '(device.enrollmentProfileName -contains "a")' }
    @{ Id = 'FLT-F19'; Rule = '(device.enrollmentProfileName -notContains "a")' }
    @{ Id = 'FLT-F20'; Rule = '(device.enrollmentProfileName -ne "a")' }
    @{ Id = 'FLT-F21'; Rule = '(device.enrollmentProfileName -notIn ["a"])' }
    @{ Id = 'FLT-F22'; Rule = '(device.enrollmentProfileName -startsWith "a")' }
    @{ Id = 'FLT-F23'; Rule = '(device.enrollmentProfileName -eq "")' }
    @{ Id = 'FLT-F25'; Rule = '(device.isTpmAttested -eq "False")' }
    @{ Id = 'FLT-F27'; Rule = '(device.operatingSystemVersion -ge "{os3}")' }
    @{ Id = 'FLT-F28'; Rule = '(device.deviceName -in [" {name} ", "x"])' }
    @{ Id = 'FLT-F29'; Rule = '(device.deviceName -contains "{name}X")' }
    @{ Id = 'FLT-F30'; Rule = '(device.deviceName -notContains "{name.head.lower}")' }
    @{ Id = 'FLT-F31'; Rule = '(device.deviceName -notIn ["nope"])' }
    @{ Id = 'FLT-F32'; Rule = '(device.operatingSystemVersion -gt {os}) or ' +
        '(device.operatingSystemVersion -lt {os})' }
    @{ Id = 'FLT-F33'; Rule = '(device.model -eq "{model}")' }
    @{ Id = 'FLT-F34'; Rule = '(device.osVersion -eq "{os} ")' }
    @{ Id = 'FLT-F35'; Rule = '(device.operatingSystemVersion -eq "{os} ")' }
    @{ Id = 'FLT-Y01'; Rule = '(device.deviceName -eq ["{name}","x"])' }
    @{ Id = 'FLT-Y02'; Rule = '(device.deviceName -ne ["{name}","x"])' }
    @{ Id = 'FLT-Y03'; Rule = '(device.deviceName -contains " ")' }
    @{ Id = 'FLT-Y04'; Rule = '(device.isTpmAttested -ne "True")' }
)
$tokens = @{
    '{name}'               = $name
    '{name.lower}'         = $name.ToLowerInvariant()
    '{name.head}'          = $name.Substring(0, 3)
    '{name.head.lower}'    = $name.Substring(0, 3).ToLowerInvariant()
    '{name.mid.lower}'     = $name.Substring(2, [Math]::Min(5, $name.Length - 2)).ToLowerInvariant()
    '{name.offset}'        = $name.Substring(1, 3)
    '{os}'                 = $osVersion
    '{os3}'                = $osShort
    '{os.build}'           = ($osVersion -split '\.')[2]
    '{model}'              = $device.model
    '{model.lower}'        = $device.model.ToLowerInvariant()
    '{model.head.upper}'   = $device.model.Substring(0, 4).ToUpperInvariant()
    '{manufacturer.lower}' = $device.manufacturer.ToLowerInvariant()
}

function Test-FilterSyntax {
    param([string]$Rule)
    $body = @{
        deviceAndAppManagementAssignmentFilter = @{
            '@odata.type' = '#microsoft.graph.deviceAndAppManagementAssignmentFilter'
            displayName = 'ISL-probe'; platform = 'windows10AndLater'; rule = $Rule
            assignmentFilterManagementType = 'devices'
        }
    }
    $requestSplat = @{
        Method = 'POST'; Uri = "$graph/deviceManagement/assignmentFilters/validateFilter"
        Body = ($body | ConvertTo-Json -Depth 5); ContentType = 'application/json'
    }
    $answer = Invoke-MgGraphRequest @requestSplat
    if ($null -ne $answer.isValidRule) { [bool]$answer.isValidRule } else { [bool]$answer.value.isValidRule }
}

function Get-FilterMatch {
    param([string]$Rule)
    $body = @{
        data = @{
            '@odata.type' = '#microsoft.graph.assignmentFilterEvaluateRequest'
            platform = 'windows10AndLater'; rule = $Rule; top = 100; skip = 0
        }
    }
    $file = Join-Path ([IO.Path]::GetTempPath()) "isl-filter-$([guid]::NewGuid().ToString('N')).json"
    try {
        $requestSplat = @{
            Method = 'POST'; Uri = "$graph/deviceManagement/evaluateAssignmentFilter"
            Body = ($body | ConvertTo-Json -Depth 5); ContentType = 'application/json'; OutputFilePath = $file
        }
        Invoke-MgGraphRequest @requestSplat
        $answer = Get-Content -Path $file -Raw | ConvertFrom-Json
        $nameIndex = [array]::IndexOf(@($answer.Columns.Name), 'deviceName')
        @($answer.Values | ForEach-Object { $_[$nameIndex] })
    }
    finally {
        Remove-Item -Path $file -ErrorAction SilentlyContinue
    }
}

$result = [ordered]@{ Device = $device; Syntax = @(); Matching = @() }
foreach ($probe in $syntax) {
    $entry = [ordered]@{ Id = $probe.Id; Rule = $probe.Rule; Valid = $null; Error = $null }
    try { $entry.Valid = Test-FilterSyntax -Rule $probe.Rule }
    catch { $entry.Error = "$($_.Exception.Message)" -replace '\s+', ' ' }
    $result.Syntax += $entry
    '{0} valid={1} {2}   <= {3}' -f $entry.Id, $entry.Valid, $entry.Error, ($probe.Rule -replace "`n", '\n')
}
foreach ($probe in $matching) {
    $rule = $probe.Rule
    foreach ($token in $tokens.Keys) { $rule = $rule.Replace($token, $tokens[$token]) }
    $entry = [ordered]@{ Id = $probe.Id; Rule = $rule; Matched = @(); Error = $null }
    try { $entry.Matched = @(Get-FilterMatch -Rule $rule) }
    catch { $entry.Error = "$($_.Exception.Message)" -replace '\s+', ' ' }
    $result.Matching += $entry
    '{0} matched=[{1}] {2}   <= {3}' -f $entry.Id, ($entry.Matched -join ','), $entry.Error, $rule
}

$null = New-Item -ItemType Directory -Path (Split-Path -Path $OutputPath -Parent) -Force
$result | ConvertTo-Json -Depth 6 | Set-Content -Path $OutputPath -Encoding utf8
"Written $OutputPath"
