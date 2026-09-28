function Get-IslFilterProperty {
    <#
    .SYNOPSIS
        The device properties a Windows assignment filter rule can use, with their operators and values.

    .DESCRIPTION
        One entry per property of the device entity on the "Windows 10 and later" platform, as the
        filter reference documents them and as the service's validateFilter accepted or refused them
        in the lab (Validation\Findings.md, "Assignment filter rules"): the operators each property
        allows, the kind of value it takes (a string, one of an enumerated set, a version) and, for
        an enumerated property, the values a Windows device can report. A rule the service refuses
        is what ConvertFrom-IslFilterRule refuses; a value outside the enumerated set is accepted by
        the service and never matches, which is what the parser warns about.

        isTpmAttested is not in the reference but the service accepts it and its evaluator returns
        it, so it is listed as undocumented. Managed-app properties (app.*) are refused on a device
        filter and are not listed; isRooted and deviceManagementType are refused on the Windows
        platform and are not listed either.

    .EXAMPLE
        (Get-IslFilterProperty)['cpuarchitecture'].Values

        amd64, x86, arm64, unknown: the values a Windows device reports (an x64 device is amd64).

    .EXAMPLE
        (Get-IslFilterProperty)['operatingsystemversion'].Operators

        eq, ne, gt, ge, lt, le: the only property with ordering operators, and no string operators.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $stringOperators = @('eq', 'ne', 'in', 'notIn', 'startsWith', 'contains', 'notContains')
    $enumOperators = @('eq', 'ne', 'in', 'notIn')
    # The SKU names the reference lists for operatingSystemSKU; the number in the comment is the
    # Win32_OperatingSystem.OperatingSystemSKU each name stands for (Get-IslFilterDeviceFact maps it)
    $skuNames = @(
        'BusinessN', 'CloudEdition', 'CloudEditionN', 'Core', 'CoreCountrySpecific', 'CoreN'
        'CoreSingleLanguage', 'Education', 'EducationN', 'Enterprise', 'EnterpriseEval', 'EnterpriseG'
        'EnterpriseGN', 'EnterpriseN', 'EnterpriseNEval', 'EnterpriseS', 'EnterpriseSEval', 'EnterpriseSN'
        'Holographic', 'IoTUAP', 'IoTUAPCommercial', 'IoTEnterprise', 'PPIPro', 'Professional'
        'ProfessionalEducation', 'ProfessionalEducationN', 'ProfessionalWorkstation', 'ProfessionalN'
        'ProfessionalSingleLanguage', 'ServerRdsh'
    )
    $entries = @(
        @{ Name = 'deviceName'; Kind = 'String'; Operators = $stringOperators }
        @{ Name = 'manufacturer'; Kind = 'String'; Operators = $stringOperators }
        @{ Name = 'model'; Kind = 'String'; Operators = $stringOperators }
        @{ Name = 'deviceCategory'; Kind = 'String'; Operators = $stringOperators }
        @{ Name = 'enrollmentProfileName'; Kind = 'String'; Operators = $stringOperators }
        @{ Name = 'osVersion'; Kind = 'String'; Operators = $stringOperators; Deprecated = $true }
        @{ Name = 'operatingSystemSKU'; Kind = 'String'; Operators = $stringOperators; Values = $skuNames }
        @{ Name = 'operatingSystemVersion'; Kind = 'Version'; Operators = @('eq', 'ne', 'gt', 'ge', 'lt', 'le') }
        @{ Name = 'cpuArchitecture'; Kind = 'Enum'; Operators = $enumOperators
            Values = @('amd64', 'x86', 'arm64', 'unknown') }
        @{ Name = 'deviceTrustType'; Kind = 'Enum'; Operators = $enumOperators
            Values = @('Azure AD joined', 'Azure AD registered', 'Hybrid Azure AD joined', 'Unknown') }
        @{ Name = 'deviceOwnership'; Kind = 'Enum'; Operators = @('eq', 'ne')
            Values = @('Personal', 'Corporate', 'Unknown') }
        @{ Name = 'isTpmAttested'; Kind = 'Enum'; Operators = @('eq', 'ne'); Values = @('True', 'False')
            Documented = $false }
    )
    $table = @{}
    foreach ($entry in $entries) {
        if (-not $entry.ContainsKey('Documented')) { $entry.Documented = $true }
        if (-not $entry.ContainsKey('Deprecated')) { $entry.Deprecated = $false }
        $table[$entry.Name.ToLowerInvariant()] = $entry
    }
    $table
}
