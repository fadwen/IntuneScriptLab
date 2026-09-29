#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The filter rule parser against what the service's validateFilter accepted and refused
    (Validation\Findings.md, "Assignment filter rules", FLT-V*, FLT-W* and FLT-X*): every accepted
    shape parses, every refused one comes back with an Error that names the reason, and the tree,
    the clause values and the warnings come out as the evaluator needs them.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force

    function script:ConvertFrom-Rule {
        param([string]$Rule)
        InModuleScope IntuneScriptLab -Parameters @{ Rule = $Rule } { ConvertFrom-IslFilterRule -Rule $Rule }
    }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertFrom-IslFilterRule' -Tag 'Unit', 'Private' {

    Context 'Rules the service accepts' {
        It 'parses <Rule> into <Clauses> clause(s)' -ForEach @(
            @{ Rule = '(device.deviceName -eq "X")'; Clauses = 1 }
            @{ Rule = '(device.deviceName eq "X")'; Clauses = 1 }
            @{ Rule = '(device.deviceName -EQ "X")'; Clauses = 1 }
            @{ Rule = '(device.DEVICENAME -eq "X")'; Clauses = 1 }
            @{ Rule = '(DEVICE.deviceName -eq "X")'; Clauses = 1 }
            @{ Rule = 'device.deviceName -eq "X"'; Clauses = 1 }
            @{ Rule = '(device.deviceName -eq "A") AND (device.model -eq "B")'; Clauses = 2 }
            @{ Rule = '(device.deviceName -eq "A") -and (device.model -eq "B")'; Clauses = 2 }
            @{ Rule = '(device.deviceName -eq "A") -or (device.model -eq "B")'; Clauses = 2 }
            @{ Rule = '(device.deviceName -in "X")'; Clauses = 1 }
            @{ Rule = '(device.deviceName -in ["X"])'; Clauses = 1 }
            @{ Rule = '(device.deviceName -in ["A"] )'; Clauses = 1 }
            @{ Rule = '(device.operatingSystemVersion -gt 10.0.22000.1000)'; Clauses = 1 }
            @{ Rule = '(device.operatingSystemVersion -gt "10.0.22000.1000")'; Clauses = 1 }
            @{ Rule = '(device.operatingSystemVersion -eq 10.0)'; Clauses = 1 }
            @{ Rule = '(device.operatingSystemVersion -ge "10.0.26100")'; Clauses = 1 }
            @{ Rule = '(device.operatingSystemVersion -gt 10.0.100000000.1)'; Clauses = 1 }
            @{ Rule = '(device.enrollmentProfileName -ne $null)'; Clauses = 1 }
            @{ Rule = '(device.enrollmentProfileName -eq null)'; Clauses = 1 }
            @{ Rule = '(device.enrollmentProfileName -eq "null")'; Clauses = 1 }
            @{ Rule = '(device.deviceTrustType -eq $null)'; Clauses = 1 }
            @{ Rule = '(device.osVersion -eq $null)'; Clauses = 1 }
            @{ Rule = '((device.deviceName -eq "A") or (device.deviceName -eq "B")) and (device.model -eq "C")'
                Clauses = 3 }
            @{ Rule = "(device.deviceName`n  -eq   `"X`" )`n"; Clauses = 1 }
            @{ Rule = '(device.deviceOwnership -eq "Personal")'; Clauses = 1 }
            @{ Rule = '(device.operatingSystemSKU -eq "Enterprise")'; Clauses = 1 }
            @{ Rule = '(device.deviceName -eq "It''s")'; Clauses = 1 }
            @{ Rule = '(device.deviceName -eq "a\b")'; Clauses = 1 }
            @{ Rule = '(device.deviceName -in ["A", "B",])'; Clauses = 1 }
            @{ Rule = '(device.deviceName -in [""])'; Clauses = 1 }
            @{ Rule = '(device.deviceName -contains " ")'; Clauses = 1 }
            @{ Rule = '(device.deviceName -eq "A") and (device.deviceName -eq "B") or (device.deviceName -eq "C")'
                Clauses = 3 }
            @{ Rule = '(device.deviceName -eq "X") and (device.deviceName -eq "Y") and (device.deviceName -eq "Z")'
                Clauses = 3 }
            @{ Rule = '(device.model -Contains "X")'; Clauses = 1 }
            @{ Rule = '(device.deviceName -notContains "A")'; Clauses = 1 }
            @{ Rule = 'device.deviceName -eq "A" and device.model -eq "B"'; Clauses = 2 }
            @{ Rule = '(device.deviceName -eq "A" and device.model -eq "B")'; Clauses = 2 }
            @{ Rule = '((device.deviceName -eq "A"))'; Clauses = 1 }
            @{ Rule = '(device.deviceName -IN ["X"]) OR (device.deviceName -NOTIN ["Y"])'; Clauses = 2 }
            @{ Rule = '(device.isTpmAttested -eq "True")'; Clauses = 1 }
            @{ Rule = '(device.isTpmAttested -ne "True")'; Clauses = 1 }
            @{ Rule = '(device.cpuArchitecture -in ["amd64","arm64"])'; Clauses = 1 }
            @{ Rule = '(device.deviceCategory -contains "Engineering")'; Clauses = 1 }
            @{ Rule = '(device.manufacturer -startsWith "Micro")'; Clauses = 1 }
        ) {
            $parsed = ConvertFrom-Rule -Rule $Rule
            $parsed.PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.FilterRule'
            $parsed.Error | Should-BeNull
            @($parsed.Clauses).Count | Should-Be $Clauses
            $parsed.Tree | Should-NotBeNull
            $parsed.Rule | Should-Be $Rule
        }
    }

    Context 'Rules the service refuses' {
        It 'refuses <Rule>' -ForEach @(
            @{ Rule = '(device.deviceName -notStartsWith "X")'; Message = '*-notStartsWith is refused*' }
            @{ Rule = '(device.deviceName -endsWith "X")'; Message = '*-endsWith is refused*' }
            @{ Rule = '(device.deviceName -notEndsWith "X")'; Message = '*-notEndsWith is refused*' }
            @{ Rule = 'not (device.deviceName -eq "X")'; Message = "*'not' is not an operator*" }
            @{ Rule = '-not (device.deviceName -eq "X")'; Message = "*'not' is not an operator*" }
            @{ Rule = '!(device.deviceName -eq "X")'; Message = "*'!' is not an operator*" }
            @{ Rule = "(device.deviceName -eq 'X')"; Message = '*must be in double quotes*' }
            @{ Rule = '(device.deviceName -eq X)'; Message = '*must be in double quotes*' }
            @{ Rule = '(device.deviceName -eq 42)'; Message = '*the value 42 must be in double quotes*' }
            @{ Rule = '(device.deviceName -gt "X")'; Message = '*-gt is not allowed on device.deviceName*' }
            @{ Rule = '(device.operatingSystemVersion -startsWith "10.0")'
                Message = '*-startsWith is not allowed on device.operatingSystemVersion*' }
            @{ Rule = '(device.osVersion -gt "10.0")'; Message = '*-gt is not allowed on device.osVersion*' }
            @{ Rule = '(device.cpuArchitecture -contains "arm")'
                Message = '*-contains is not allowed on device.cpuArchitecture*' }
            @{ Rule = '(device.cpuArchitecture -startsWith "arm")'
                Message = '*-startsWith is not allowed on device.cpuArchitecture*' }
            @{ Rule = '(device.deviceTrustType -contains "joined")'
                Message = '*-contains is not allowed on device.deviceTrustType*' }
            @{ Rule = '(device.deviceOwnership -startsWith "Pers")'
                Message = '*-startsWith is not allowed on device.deviceOwnership*' }
            @{ Rule = '(device.deviceOwnership -in ["Personal"])'
                Message = '*-in is not allowed on device.deviceOwnership*' }
            @{ Rule = '(device.operatingSystemVersion -in ["10.0.22000.1000"])'
                Message = '*-in is not allowed on device.operatingSystemVersion*' }
            @{ Rule = '(device.deviceName -startsWith $null)'
                Message = '*$null is accepted with -eq and -ne only*' }
            @{ Rule = '(device.enrollmentProfileName -contains $null)'
                Message = '*$null is accepted with -eq and -ne only*' }
            @{ Rule = '(device.operatingSystemVersion -eq $null)'; Message = '*cannot be compared with $null*' }
            @{ Rule = '(device.noSuchProperty -eq "X")'; Message = '*unknown property device.noSuchProperty*' }
            @{ Rule = '(device.isRooted -eq "True")'; Message = '*unknown property device.isRooted*' }
            @{ Rule = '(device.deviceManagementType -eq "X")'; Message = '*unknown property*' }
            @{ Rule = '(device.deviceId -eq "X")'; Message = '*unknown property device.deviceId*' }
            @{ Rule = '(device.userPrincipalName -eq "X")'; Message = '*unknown property*' }
            @{ Rule = '(app.deviceModel -eq "X")'; Message = '*managed app property*' }
            @{ Rule = '(user.deviceName -eq "X")'; Message = "*unknown entity 'user'*" }
            @{ Rule = '(device.deviceName -contains "")'; Message = '*empty string is refused*' }
            @{ Rule = '(device.deviceName -eq "")'; Message = '*empty string is refused*' }
            @{ Rule = '(device.deviceName -ne "")'; Message = '*empty string is refused*' }
            @{ Rule = '(device.deviceName -startsWith "")'; Message = '*empty string is refused*' }
            @{ Rule = '(device.deviceName -eq "X") (device.model -eq "Y")'
                Message = "*expected 'and' or 'or' before '('*" }
            @{ Rule = '(device.deviceName -eq "ab" "cd")'; Message = "*expected 'and', 'or' or ')'*found 'cd'*" }
            @{ Rule = '(device.deviceName -eq "X") // comment'; Message = "*expected 'and' or 'or' before '//'*" }
            @{ Rule = '(device.deviceName -eq "X") xor (device.model -eq "Y")'
                Message = "*expected 'and' or 'or' before 'xor'*" }
            @{ Rule = '(device.deviceName -eq "say \"hi\"")'
                Message = "*expected 'and', 'or' or ')'*found 'hi\'*" }
            @{ Rule = '(device.deviceName -eq "X") or'; Message = '*expected a clause or "(" at the end*' }
            @{ Rule = '(device.deviceName -eq "X") and'; Message = '*expected a clause or "(" at the end*' }
            @{ Rule = '(device.deviceName -eq "X") or ()'; Message = "*unexpected ')'*" }
            @{ Rule = '(device.deviceName -eq "X"))'; Message = "*unexpected ')'*" }
            @{ Rule = '((device.deviceName -eq "X")'; Message = '*is not closed*' }
            @{ Rule = '(device.deviceName -eq "X"'; Message = '*is not closed*' }
            @{ Rule = '(device.deviceName-eq"X")'; Message = '*is not a property*' }
            @{ Rule = '(device.deviceName -eq)'; Message = "*expected a value after -eq*found ')'*" }
            @{ Rule = '(device.deviceName "X")'; Message = '*expected an operator after device.deviceName*' }
            @{ Rule = '(device.deviceName -equals "X")'; Message = '*-equals is refused*' }
            @{ Rule = '(device.deviceName -notEquals "X")'; Message = '*-notEquals is refused*' }
            @{ Rule = '(device.deviceName -like "X")'; Message = "*unknown operator '-like'*" }
            @{ Rule = '(device.operatingSystemVersion -eq 10)'
                Message = '*not a version of 2 to 4 numeric parts*' }
            @{ Rule = '(device.operatingSystemVersion -gt 10.0.22000.1000.5)'
                Message = '*not a version of 2 to 4 numeric parts*' }
            @{ Rule = '(device.operatingSystemVersion -eq "ten")'
                Message = '*not a version of 2 to 4 numeric parts*' }
            @{ Rule = '(device.deviceName -in [])'; Message = '*is empty*' }
            @{ Rule = '(device.deviceName -in ["A", $null])'; Message = '*list holds double-quoted strings only*' }
            @{ Rule = '(device.deviceName -in [A])'; Message = '*list holds double-quoted strings only*' }
            @{ Rule = '(device.deviceName -in ["A" "B"])'; Message = "*expected ',' or ']'*" }
            @{ Rule = '(device.deviceName -in ["A"'; Message = '*list opened at position * is not closed*' }
            @{ Rule = '(device.deviceName -eq ["A","B"])'; Message = '*-eq takes a single value*' }
            @{ Rule = '(device.deviceName -startsWith ["A"])'; Message = '*-startsWith takes a single value*' }
            @{ Rule = '(device.operatingSystemVersion -eq [10.0])'
                Message = '*list holds double-quoted strings only*' }
            @{ Rule = ''; Message = '*rule is empty*' }
            @{ Rule = '   '; Message = '*rule is empty*' }
            @{ Rule = 'and (device.deviceName -eq "X")'; Message = "*expected a clause before 'and'*" }
            @{ Rule = '(device.deviceName -eq "unterminated)'; Message = "*unexpected character '`"'*" }
        ) {
            $parsed = ConvertFrom-Rule -Rule $Rule
            $parsed.Error | Should-BeLikeString "Filter rule: $Message"
            $parsed.Tree | Should-BeNull
            @($parsed.Clauses).Count | Should-Be 0
        }
    }

    Context 'Tree and clauses' {
        It 'binds and tighter than or (FLT-E27, FLT-E28, FLT-F09)' {
            $rule = '(device.deviceName -eq "A") or (device.deviceName -eq "B") and (device.deviceName -eq "C")'
            $parsed = ConvertFrom-Rule -Rule $rule
            $parsed.Tree.Type | Should-Be 'Or'
            $parsed.Tree.Left.Type | Should-Be 'Clause'
            $parsed.Tree.Right.Type | Should-Be 'And'
            $rule = '(device.deviceName -eq "A") and (device.deviceName -eq "B") or (device.deviceName -eq "C")'
            $other = ConvertFrom-Rule -Rule $rule
            $other.Tree.Type | Should-Be 'Or'
            $other.Tree.Left.Type | Should-Be 'And'
        }

        It 'lets parentheses override the precedence' {
            $rule = '((device.deviceName -eq "A") or (device.deviceName -eq "B")) and (device.deviceName -eq "C")'
            $parsed = ConvertFrom-Rule -Rule $rule
            $parsed.Tree.Type | Should-Be 'And'
            $parsed.Tree.Left.Type | Should-Be 'Or'
        }

        It 'normalizes the property, the operator and keeps the clause text and position' {
            $parsed = ConvertFrom-Rule -Rule '  (device.DEVICENAME -EQ "X")'
            $clause = $parsed.Clauses[0]
            $clause.PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.FilterClause'
            $clause.Property | Should-Be 'deviceName'
            $clause.Kind | Should-Be 'String'
            $clause.Operator | Should-BeString 'eq' -CaseSensitive
            $clause.Value | Should-Be 'X'
            $clause.Text | Should-Be 'device.DEVICENAME -EQ "X"'
            $clause.Position | Should-Be 4
            $clause.Matched | Should-BeNull
            (ConvertFrom-Rule -Rule '(device.model -Contains "X")').Clauses[0].Operator |
                Should-BeString 'contains' -CaseSensitive
            (ConvertFrom-Rule -Rule '(device.deviceName -NOTIN ["X"])').Clauses[0].Operator |
                Should-BeString 'notIn' -CaseSensitive
        }

        It 'reads a single string after -in as a one-item list (FLT-V18, FLT-F02)' {
            $clause = (ConvertFrom-Rule -Rule '(device.deviceName -in "X")').Clauses[0]
            @($clause.Value).Count | Should-Be 1
            $clause.Value[0] | Should-Be 'X'
        }

        It 'keeps every list item and tolerates a trailing comma (FLT-V46)' {
            $clause = (ConvertFrom-Rule -Rule '(device.deviceName -in ["A", "B",])').Clauses[0]
            @($clause.Value) | Should-BeCollection @('A', 'B')
        }

        It 'reads $null and null as a null value' {
            (ConvertFrom-Rule -Rule '(device.deviceCategory -eq $null)').Clauses[0].Value | Should-BeNull
            (ConvertFrom-Rule -Rule '(device.deviceCategory -ne NULL)').Clauses[0].Value | Should-BeNull
        }

        It 'reads a version quoted or bare' {
            $bare = (ConvertFrom-Rule -Rule '(device.operatingSystemVersion -gt 10.0.22000.1000)').Clauses[0]
            $bare.Kind | Should-Be 'Version'
            $bare.Value | Should-Be '10.0.22000.1000'
            $quoted = (ConvertFrom-Rule -Rule '(device.operatingSystemVersion -le "10.0.22631.3235")').Clauses[0]
            $quoted.Value | Should-Be '10.0.22631.3235'
            $quoted.Operator | Should-Be 'le'
        }

        It 'lists the clauses in rule order' {
            $rule = '(device.model -eq "M") or ((device.deviceName -eq "D") and (device.manufacturer -eq "V"))'
            (ConvertFrom-Rule -Rule $rule).Clauses.Property |
                Should-BeCollection @('model', 'deviceName', 'manufacturer')
        }
    }

    Context 'Warnings' {
        It 'warns that <Rule> uses a value no Windows device reports' -ForEach @(
            @{ Rule = '(device.cpuArchitecture -eq "x64")'; Kind = 'NeverMatches'
                Text = "*'x64'*device.cpuArchitecture*never matches*" }
            @{ Rule = '(device.cpuArchitecture -in ["amd64", "x64"])'; Kind = 'NeverMatches'
                Text = "*'x64'*never matches*" }
            @{ Rule = '(device.deviceTrustType -eq "Microsoft Entra joined")'; Kind = 'NeverMatches'
                Text = "*'Microsoft Entra joined'*device.deviceTrustType*" }
            # -ne with a value nobody reports is true for every device, the opposite trap
            @{ Rule = '(device.deviceTrustType -ne "AzureADJoined")'; Kind = 'AlwaysMatches'
                Text = "*'AzureADJoined'*matches every device*" }
            @{ Rule = '(device.deviceOwnership -eq "company")'; Kind = 'NeverMatches'
                Text = "*'company'*Personal, Corporate, Unknown*" }
            @{ Rule = '(device.operatingSystemSKU -eq "Windows Enterprise")'; Kind = 'NeverMatches'
                Text = "*'Windows Enterprise'*" }
        ) {
            $parsed = ConvertFrom-Rule -Rule $Rule
            @($parsed.Warnings).Count | Should-Be 1
            $parsed.Warnings[0].Kind | Should-Be $Kind
            $parsed.Warnings[0].Message | Should-BeLikeString $Text
        }

        It 'does not warn about documented values, in any casing, or partial matches' -ForEach @(
            @{ Rule = '(device.cpuArchitecture -eq "ARM64")' }
            @{ Rule = '(device.deviceTrustType -in ["Hybrid Azure AD joined","Azure AD joined"])' }
            @{ Rule = '(device.operatingSystemSKU -startsWith "Ent")' }
            @{ Rule = '(device.operatingSystemSKU -eq "EnterpriseSEval")' }
            @{ Rule = '(device.deviceTrustType -eq $null)' }
        ) {
            @((ConvertFrom-Rule -Rule $Rule).Warnings).Count | Should-Be 0
        }

        It 'flags the deprecated osVersion and the undocumented isTpmAttested' {
            $deprecated = (ConvertFrom-Rule -Rule '(device.osVersion -startsWith "10.0")').Warnings
            @($deprecated).Count | Should-Be 1
            $deprecated[0].Kind | Should-Be 'Deprecated'
            $deprecated[0].Message | Should-BeLikeString '*device.osVersion is deprecated*operatingSystemVersion*'
            $undocumented = (ConvertFrom-Rule -Rule '(device.isTpmAttested -eq "True")').Warnings
            @($undocumented).Count | Should-Be 1
            $undocumented[0].Kind | Should-Be 'Undocumented'
        }
    }
}
