#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The filter evaluator against what the service's filter evaluator matched for the joined lab
    device KRBETYP-AIEPVQ5 (Validation\Findings.md, "Assignment filter rules", FLT-E* and FLT-F*):
    the device is described with the values the service returned for it, and each rule must match
    or not match the way the service did. The local device facts are mocked.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    # The joined lab device as the filter evaluator returned it (FLT-E01)
    $script:Joined = @{
        deviceName             = 'KRBETYP-AIEPVQ5'
        manufacturer           = 'QEMU'
        model                  = 'Standard PC (Q35 + ICH9, 2009)'
        osVersion              = '10.0.26100.9457'
        operatingSystemVersion = '10.0.26100.9457'
        operatingSystemSKU     = 'EnterpriseSEval'
        cpuArchitecture        = 'amd64'
        deviceTrustType        = 'Azure AD joined'
        deviceOwnership        = 'Corporate'
        enrollmentProfileName  = $null
        deviceCategory         = $null
        isTpmAttested          = 'False'
    }
    $script:Me = '(device.deviceName -eq "KRBETYP-AIEPVQ5")'
    $script:Nobody = '(device.deviceName -eq "nope")'
    $script:Registered = '(device.deviceTrustType -eq "Azure AD registered")'
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Test-IntuneAssignmentFilter' -Tag 'Unit', 'Public' {

    Context 'Matching as the service matched it' {
        It '<Rule> matched=<Expected>' -ForEach @(
            @{ Rule = '(device.deviceName -eq "krbetyp-aiepvq5")'; Expected = $true }
            @{ Rule = '(device.deviceName -contains "betyp")'; Expected = $true }
            @{ Rule = '(device.deviceName -contains "krbetyp-")'; Expected = $true }
            @{ Rule = '(device.deviceName -contains "KRBETYP-AIEPVQ5X")'; Expected = $false }
            @{ Rule = '(device.deviceName -contains " ")'; Expected = $true }
            @{ Rule = '(device.deviceName -startsWith "KRB")'; Expected = $true }
            @{ Rule = '(device.deviceName -startsWith "RBE")'; Expected = $false }
            @{ Rule = '(device.deviceName -startsWith " KRB")'; Expected = $true }
            @{ Rule = '(device.deviceName -in ["KRBETYP-AIEPVQ5","nope"])'; Expected = $true }
            @{ Rule = '(device.deviceName -in ["krbetyp-aiepvq5"])'; Expected = $true }
            @{ Rule = '(device.deviceName -in "KRBETYP-AIEPVQ5")'; Expected = $true }
            @{ Rule = '(device.deviceName -in [" KRBETYP-AIEPVQ5 ", "x"])'; Expected = $true }
            @{ Rule = '(device.deviceName -notIn ["KRBETYP-AIEPVQ5"])'; Expected = $false }
            @{ Rule = '(device.deviceName -notIn ["nope"])'; Expected = $true }
            @{ Rule = '(device.deviceName -eq "KRBETYP-AIEPVQ5 ")'; Expected = $true }
            @{ Rule = '(device.deviceName -eq " KRBETYP-AIEPVQ5")'; Expected = $true }
            @{ Rule = '(device.deviceName -ne "KRBETYP-AIEPVQ5")'; Expected = $false }
            @{ Rule = '(device.deviceName -ne $null)'; Expected = $true }
            @{ Rule = '(device.deviceName -notContains "ZZZQ")'; Expected = $true }
            @{ Rule = '(device.deviceName -notContains "krbetyp")'; Expected = $false }
            @{ Rule = '(device.cpuArchitecture -eq "amd64")'; Expected = $true }
            @{ Rule = '(device.cpuArchitecture -eq "x64")'; Expected = $false }
            @{ Rule = '(device.cpuArchitecture -in ["amd64","arm64"])'; Expected = $true }
            @{ Rule = '(device.deviceTrustType -eq "Azure AD joined")'; Expected = $true }
            @{ Rule = '(device.deviceTrustType -eq "Azure AD registered")'; Expected = $false }
            @{ Rule = '(device.deviceTrustType -eq "AzureADJoined")'; Expected = $false }
            @{ Rule = '(device.deviceTrustType -eq "Microsoft Entra joined")'; Expected = $false }
            @{ Rule = '(device.deviceTrustType -in ["Hybrid Azure AD joined","Azure AD joined"])'
                Expected = $true }
            @{ Rule = '(device.operatingSystemVersion -gt 10.0.22000.1000)'; Expected = $true }
            @{ Rule = '(device.operatingSystemVersion -eq 10.0.26100.9457)'; Expected = $true }
            @{ Rule = '(device.operatingSystemVersion -eq "10.0.26100.9457")'; Expected = $true }
            @{ Rule = '(device.operatingSystemVersion -eq "10.0.26100.9457 ")'; Expected = $true }
            @{ Rule = '(device.operatingSystemVersion -eq 10.0.26100)'; Expected = $false }
            @{ Rule = '(device.operatingSystemVersion -ge 10.0.26100)'; Expected = $true }
            @{ Rule = '(device.operatingSystemVersion -ge "10.0.26100")'; Expected = $true }
            @{ Rule = '(device.operatingSystemVersion -gt 10.0.26100.0)'; Expected = $true }
            @{ Rule = '(device.operatingSystemVersion -lt 10.0.26100.9457)'; Expected = $false }
            @{ Rule = '(device.operatingSystemVersion -ne 10.0.26100.9457)'; Expected = $false }
            @{ Rule = '(device.operatingSystemVersion -gt 10.0.26100.9457) or ' +
                '(device.operatingSystemVersion -lt 10.0.26100.9457)'; Expected = $false }
            @{ Rule = '(device.operatingSystemVersion -le 10.0.26100.9457)'; Expected = $true }
            @{ Rule = '(device.osVersion -startsWith "10.0.26100")'; Expected = $true }
            @{ Rule = '(device.osVersion -eq "10.0.26100.9457")'; Expected = $true }
            @{ Rule = '(device.osVersion -eq "10.0.26100.9457 ")'; Expected = $true }
            @{ Rule = '(device.osVersion -eq "10.0.26100")'; Expected = $false }
            @{ Rule = '(device.osVersion -in ["10.0.26100.9457", "1.0"])'; Expected = $true }
            @{ Rule = '(device.osVersion -contains "26100")'; Expected = $true }
            @{ Rule = '(device.manufacturer -eq "qemu")'; Expected = $true }
            @{ Rule = '(device.manufacturer -in ["qemu"])'; Expected = $true }
            @{ Rule = '(device.model -eq "standard pc (q35 + ich9, 2009)")'; Expected = $true }
            @{ Rule = '(device.model -eq "Standard PC (Q35 + ICH9, 2009)")'; Expected = $true }
            @{ Rule = '(device.model -contains "STAN")'; Expected = $true }
            @{ Rule = '(device.model -contains "(q35")'; Expected = $true }
            @{ Rule = '(device.operatingSystemSKU -eq "Enterprise")'; Expected = $false }
            @{ Rule = '(device.operatingSystemSKU -eq "EnterpriseSEval")'; Expected = $true }
            @{ Rule = '(device.operatingSystemSKU -startsWith "enterprise")'; Expected = $true }
            @{ Rule = '(device.operatingSystemSKU -in ["Enterprise","EnterpriseSEval"])'; Expected = $true }
            @{ Rule = '(device.enrollmentProfileName -eq $null)'; Expected = $true }
            @{ Rule = '(device.enrollmentProfileName -ne $null)'; Expected = $false }
            @{ Rule = '(device.enrollmentProfileName -contains "a")'; Expected = $false }
            @{ Rule = '(device.enrollmentProfileName -notContains "a")'; Expected = $true }
            @{ Rule = '(device.enrollmentProfileName -ne "a")'; Expected = $true }
            @{ Rule = '(device.enrollmentProfileName -notIn ["a"])'; Expected = $true }
            @{ Rule = '(device.enrollmentProfileName -startsWith "a")'; Expected = $false }
            @{ Rule = '(device.deviceOwnership -eq "Corporate")'; Expected = $true }
            @{ Rule = '(device.deviceOwnership -eq "Personal")'; Expected = $false }
            @{ Rule = '(device.deviceOwnership -eq "company")'; Expected = $false }
            @{ Rule = '(device.deviceCategory -eq $null)'; Expected = $true }
            @{ Rule = '(device.deviceCategory -ne $null)'; Expected = $false }
            @{ Rule = '(device.deviceCategory -eq "Unknown")'; Expected = $false }
            @{ Rule = '(device.isTpmAttested -eq "False")'; Expected = $true }
            @{ Rule = '(device.isTpmAttested -ne "True")'; Expected = $true }
        ) {
            $result = Test-IntuneAssignmentFilter -Rule $Rule -Device $script:Joined 3>$null
            $result.Matched | Should-Be $Expected
            $result.Applicable | Should-Be $Expected
        }

        It 'binds and before or, and lets parentheses override it (FLT-E27, FLT-E28, FLT-F07 to FLT-F09)' {
            $cases = @(
                @{ Rule = "$script:Me or $script:Nobody and $script:Nobody"; Expected = $true }
                @{ Rule = "$script:Nobody and $script:Nobody or $script:Me"; Expected = $true }
                @{ Rule = "$script:Me and $script:Registered"; Expected = $false }
                @{ Rule = "($script:Nobody or $script:Me) and $script:Registered"; Expected = $false }
                @{ Rule = "$script:Nobody or $script:Me and $script:Registered"; Expected = $false }
                @{ Rule = "$script:Me or (device.deviceName -eq `"KRBETYP-R5LTADM`")"; Expected = $true }
            )
            foreach ($case in $cases) {
                $result = Test-IntuneAssignmentFilter -Rule $case.Rule -Device $script:Joined
                $result.Matched | Should-Be $case.Expected -Because $case.Rule
            }
        }
    }

    Context 'Core Functionality' {
        It 'returns the verdict, the reason and every clause with what it saw' {
            $rule = '(device.deviceName -startsWith "LAB-") and (device.cpuArchitecture -eq "amd64")'
            $result = Test-IntuneAssignmentFilter -Rule $rule -Device $script:Joined
            $result.PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.FilterResult'
            $result.Rule | Should-Be $rule
            $result.Mode | Should-Be 'Include'
            $result.Matched | Should-BeFalse
            $result.Applicable | Should-BeFalse
            $result.Reason |
                Should-BeLikeString 'Not applicable:*Filters criteria are not met.*W32-FILTER-INCLUDE*'
            @($result.Clauses).Count | Should-Be 2
            $result.Clauses[0].Actual | Should-Be 'KRBETYP-AIEPVQ5'
            $result.Clauses[0].Matched | Should-BeFalse
            $result.Clauses[1].Actual | Should-Be 'amd64'
            $result.Clauses[1].Matched | Should-BeTrue
            $result.Device.deviceName | Should-Be 'KRBETYP-AIEPVQ5'
            @($result.Warnings).Count | Should-Be 0
        }

        It 'reports a matched include rule as applicable' {
            $result = Test-IntuneAssignmentFilter -Rule '(device.manufacturer -eq "QEMU")' -Device $script:Joined
            $result.Applicable | Should-BeTrue
            $result.Reason | Should-BeLikeString 'Included: the rule matches*'
        }

        It 'inverts the verdict for an exclude filter (W32-FILTER-EXCLUDE)' {
            $excludeSplat = @{ Device = $script:Joined; Mode = 'Exclude' }
            $hit = Test-IntuneAssignmentFilter -Rule '(device.manufacturer -eq "QEMU")' @excludeSplat
            $hit.Matched | Should-BeTrue
            $hit.Applicable | Should-BeFalse
            $hit.Reason | Should-BeLikeString 'Not applicable: the exclude rule matches*W32-FILTER-EXCLUDE*'
            $miss = Test-IntuneAssignmentFilter -Rule '(device.manufacturer -eq "Dell")' @excludeSplat
            $miss.Matched | Should-BeFalse
            $miss.Applicable | Should-BeTrue
            $miss.Reason | Should-BeLikeString 'Included: the exclude rule does not match*'
        }

        It 'reads the device properties case-insensitively, from a hashtable or an object' {
            $upper = @{ DEVICENAME = 'LAB-1'; CpuArchitecture = 'arm64' }
            $byName = Test-IntuneAssignmentFilter -Rule '(device.deviceName -eq "lab-1")' -Device $upper
            $byName.Matched | Should-BeTrue
            $object = [pscustomobject]@{ deviceName = 'LAB-2'; cpuArchitecture = 'arm64' }
            $byArch = Test-IntuneAssignmentFilter -Rule '(device.cpuArchitecture -eq "ARM64")' -Device $object
            $byArch.Matched | Should-BeTrue
            $result = Test-IntuneAssignmentFilter -Rule '(device.model -eq $null)' -Device $object
            $result.Matched | Should-BeTrue
            $result.Clauses[0].Actual | Should-BeNull
        }

        It 'treats a value that is not a version as never ordered, and unequal' {
            $odd = @{ operatingSystemVersion = 'unknown' }
            $greater = Test-IntuneAssignmentFilter -Rule '(device.operatingSystemVersion -gt 10.0)' -Device $odd
            $greater.Matched | Should-BeFalse
            $lesser = Test-IntuneAssignmentFilter -Rule '(device.operatingSystemVersion -le 10.0)' -Device $odd
            $lesser.Matched | Should-BeFalse
            $unequal = Test-IntuneAssignmentFilter -Rule '(device.operatingSystemVersion -ne 10.0)' -Device $odd
            $unequal.Matched | Should-BeTrue
        }

        It 'validates the syntax without a device on request' {
            $result = Test-IntuneAssignmentFilter -Rule '(device.cpuArchitecture -eq "x64")' -SyntaxOnly 3>$null
            $result.Matched | Should-BeNull
            $result.Applicable | Should-BeNull
            $result.Reason | Should-Be 'The rule is valid: 1 clause(s), 1 warning(s)'
            $result.Clauses[0].Matched | Should-BeNull
            @($result.Warnings).Count | Should-Be 1
        }

        It 'surfaces the parser warnings as warnings and on the result' {
            $warnings = @()
            $warnSplat = @{ Rule = '(device.cpuArchitecture -eq "x64")'; Device = $script:Joined }
            $result = Test-IntuneAssignmentFilter @warnSplat -WarningVariable warnings 3>$null
            @($warnings).Count | Should-Be 1
            "$($warnings[0])" | Should-BeLikeString "*'x64'*never matches*"
            $result.Warnings[0] | Should-BeLikeString "*'x64'*"
            $result.Matched | Should-BeFalse
        }

        It 'reads the local device when none is given' {
            Mock Get-IslFilterDeviceFact -ModuleName IntuneScriptLab {
                @{ deviceName = 'LOCAL-1'; cpuArchitecture = 'arm64' }
            }
            $result = Test-IntuneAssignmentFilter -Rule '(device.deviceName -eq "local-1")'
            $result.Matched | Should-BeTrue
            $result.Device.cpuArchitecture | Should-Be 'arm64'
            Should-Invoke Get-IslFilterDeviceFact -ModuleName IntuneScriptLab -Times 1 -Exactly
        }

        It 'does not read the local device for a syntax check' {
            Mock Get-IslFilterDeviceFact -ModuleName IntuneScriptLab { throw 'should not be read' }
            $result = Test-IntuneAssignmentFilter -Rule '(device.deviceName -eq "x")' -SyntaxOnly
            $result.Reason | Should-BeLikeString 'The rule is valid*'
        }
    }

    Context 'Pipeline' {
        It 'takes rules from the pipeline, as strings or as objects with a Rule property' {
            $rules = '(device.deviceName -eq "KRBETYP-AIEPVQ5")', '(device.deviceName -eq "other")'
            $results = @($rules | Test-IntuneAssignmentFilter -Device $script:Joined)
            $results.Count | Should-Be 2
            $results.Matched | Should-BeCollection @($true, $false)
            $filters = @(
                [pscustomobject]@{ displayName = 'A'; rule = '(device.manufacturer -eq "QEMU")' }
                [pscustomobject]@{ displayName = 'B'; rule = '(device.manufacturer -eq "Dell")' }
            )
            $fromObjects = @($filters | Test-IntuneAssignmentFilter -Device $script:Joined)
            $fromObjects.Matched | Should-BeCollection @($true, $false)
        }
    }

    Context 'Error Handling' {
        It 'writes one non-terminating error for a rule the service refuses, and keeps going' {
            $errors = @()
            $rules = '(device.deviceName -eq X)', '(device.deviceName -eq "X")'
            $errorSplat = @{ Device = $script:Joined; ErrorVariable = 'errors'; ErrorAction = 'SilentlyContinue' }
            $results = @($rules | Test-IntuneAssignmentFilter @errorSplat)
            $results.Count | Should-Be 1
            @($errors).Count | Should-Be 1
            $errors[0].FullyQualifiedErrorId | Should-BeLikeString 'IslFilterRuleInvalid*'
            $errors[0].TargetObject | Should-Be '(device.deviceName -eq X)'
            $errors[0].Exception.Message | Should-BeLikeString 'Filter rule:*double quotes*'
        }

        It 'terminates on an invalid rule with -ErrorAction Stop' {
            { Test-IntuneAssignmentFilter -Rule '(device.deviceName -like "X")' -Device @{} -ErrorAction Stop } |
                Should-Throw -ExceptionMessage '*unknown operator*'
        }
    }
}
