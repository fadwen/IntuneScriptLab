function Get-IslFilterDeviceFact {
    <#
    .SYNOPSIS
        Reads this device's values for the properties an assignment filter rule compares.

    .DESCRIPTION
        The values the filter evaluator returned for the lab devices, read from the same places on
        the local machine: deviceName from the computer name; manufacturer and model from
        Win32_ComputerSystem; osVersion and operatingSystemVersion as major.minor.build.UBR from the
        CurrentVersion registry key (10.0.26100.9457 on the lab devices); operatingSystemSKU as the
        name the filter reference gives the Win32_OperatingSystem SKU number (129 was
        EnterpriseSEval); cpuArchitecture as amd64, x86 or arm64 (an x64 device is amd64, and a rule
        saying "x64" never matches); deviceTrustType from dsregcmd /status; deviceOwnership
        inferred from the join type (Corporate for a joined device, Personal for a registered one,
        as the lab devices reported). enrollmentProfileName, deviceCategory and isTpmAttested live
        in the tenant, not on the device, and are left null, which a rule can test with -eq $null.

        Windows only: it reads CIM, the registry and dsregcmd. Pass -Device to
        Test-IntuneAssignmentFilter on other platforms.

    .EXAMPLE
        Get-IslFilterDeviceFact

        A hashtable with one entry per filter property.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $onWindows = $PSVersionTable.PSVersion.Major -lt 6 -or $IsWindows
    if (-not $onWindows) {
        throw 'The local device facts come from Windows (CIM, the registry, dsregcmd); pass -Device elsewhere'
    }

    $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    $versionKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $version = Get-ItemProperty -Path $versionKey -ErrorAction SilentlyContinue
    $osVersion = if ($version -and $version.CurrentMajorVersionNumber) {
        "$($version.CurrentMajorVersionNumber).$($version.CurrentMinorVersionNumber)." +
        "$($version.CurrentBuildNumber).$($version.UBR)"
    }
    else { [Environment]::OSVersion.Version.ToString() }

    $architecture = switch ("$([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)") {
        'Arm64' { 'arm64' }
        'X64' { 'amd64' }
        'X86' { 'x86' }
        default { 'unknown' }
    }

    # The reference's SKU names by Win32_OperatingSystem.OperatingSystemSKU. The reference prints
    # Home as "Core (10/111)" and Professional N as "BusinessN (49)"; the numbers here are what
    # Windows reports, the names what the service compares against.
    $skuNames = @{
        4 = 'Enterprise'; 27 = 'EnterpriseN'; 48 = 'Professional'; 49 = 'BusinessN'; 72 = 'EnterpriseEval'
        84 = 'EnterpriseNEval'; 98 = 'CoreN'; 99 = 'CoreCountrySpecific'; 100 = 'CoreSingleLanguage'
        101 = 'Core'; 119 = 'PPIPro'; 121 = 'Education'; 122 = 'EducationN'; 123 = 'IoTUAP'
        125 = 'EnterpriseS'; 126 = 'EnterpriseSN'; 129 = 'EnterpriseSEval'; 131 = 'IoTUAPCommercial'
        136 = 'Holographic'; 138 = 'ProfessionalSingleLanguage'; 161 = 'ProfessionalWorkstation'
        162 = 'ProfessionalN'; 164 = 'ProfessionalEducation'; 165 = 'ProfessionalEducationN'
        171 = 'EnterpriseG'; 172 = 'EnterpriseGN'; 175 = 'ServerRdsh'; 188 = 'IoTEnterprise'
        202 = 'CloudEditionN'; 203 = 'CloudEdition'
    }
    $skuNumber = if ($operatingSystem) { [int]$operatingSystem.OperatingSystemSKU } else { 0 }
    $sku = if ($skuNames.ContainsKey($skuNumber)) { $skuNames[$skuNumber] } else { "$skuNumber" }

    $status = @(Get-IslDsregStatus)
    $joined = [bool]($status | Where-Object { $_ -match '^\s*AzureAdJoined\s*:\s*YES' })
    $domainJoined = [bool]($status | Where-Object { $_ -match '^\s*DomainJoined\s*:\s*YES' })
    $registered = [bool]($status | Where-Object { $_ -match '^\s*WorkplaceJoined\s*:\s*YES' })
    $trustType = if ($joined -and $domainJoined) { 'Hybrid Azure AD joined' }
    elseif ($joined) { 'Azure AD joined' }
    elseif ($registered) { 'Azure AD registered' }
    else { 'Unknown' }
    $ownership = switch ($trustType) {
        'Azure AD registered' { 'Personal' }
        'Unknown' { 'Unknown' }
        default { 'Corporate' }
    }

    @{
        deviceName             = $env:COMPUTERNAME
        manufacturer           = if ($computer) { "$($computer.Manufacturer)" } else { '' }
        model                  = if ($computer) { "$($computer.Model)" } else { '' }
        osVersion              = $osVersion
        operatingSystemVersion = $osVersion
        operatingSystemSKU     = $sku
        cpuArchitecture        = $architecture
        deviceTrustType        = $trustType
        deviceOwnership        = $ownership
        enrollmentProfileName  = $null
        deviceCategory         = $null
        isTpmAttested          = $null
    }
}
