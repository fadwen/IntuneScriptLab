#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    File, registry and MSI rules applied to this machine, each case mirroring a round-5 experiment
    (Validation\Findings.md, "Win32 file, registry and MSI rules"). Files live under TestDrive, a
    registry key under HKCU and a fake per-user MSI product are created for the run and removed
    afterwards; the 32-bit registry view is read from a Windows value that differs between views.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force

    $script:Fixtures = Join-Path $TestDrive 'Fixtures'
    $null = New-Item -ItemType Directory -Path $script:Fixtures -Force
    [IO.File]::WriteAllText((Join-Path $script:Fixtures 'present.txt'), 'present')
    (Get-Item (Join-Path $script:Fixtures 'present.txt')).LastWriteTimeUtc =
        [datetime]::new(2024, 6, 15, 12, 0, 0, [DateTimeKind]::Utc)
    $stream = [IO.File]::Create((Join-Path $script:Fixtures 'big.bin'))
    try { $stream.SetLength(2MB) } finally { $stream.Dispose() }
    $notepad = Join-Path $env:WINDIR 'System32\notepad.exe'
    $script:HasVersioned = Test-Path $notepad
    if ($script:HasVersioned) { Copy-Item $notepad (Join-Path $script:Fixtures 'versioned.exe') }

    $script:KeyPath = 'HKEY_CURRENT_USER\SOFTWARE\IntuneScriptLabTests'
    $script:Key = 'HKCU:\SOFTWARE\IntuneScriptLabTests'
    $null = New-Item -Path $script:Key -Force
    New-ItemProperty -Path $script:Key -Name Name -Value 'IntuneScriptLab' -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $script:Key -Name Build -Value 42 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $script:Key -Name BuildText -Value '42' -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $script:Key -Name Version -Value '10.0.1' -PropertyType String -Force | Out-Null

    $script:Code = '{0D0F9D9B-3F0E-4B2A-9C7B-ISLTEST00002}'
    $script:MsiKey = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$($script:Code)"
    $null = New-Item -Path $script:MsiKey -Force
    Set-ItemProperty -Path $script:MsiKey -Name DisplayName -Value 'ISL Test Product'
    Set-ItemProperty -Path $script:MsiKey -Name DisplayVersion -Value '110.0.2'
}

AfterAll {
    Remove-Item -Path $script:Key, $script:MsiKey -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Test-IntuneWin32Rule' -Tag 'Unit', 'Public' {

    Context 'Parameter Validation' {
        It 'refuses a comparison without an operator and value' {
            { Test-IntuneWin32Rule -Path $script:Fixtures -FileOrFolderName 'big.bin' -FileOperation SizeInMB } |
                Should-Throw -ExceptionMessage '*-Operator and -Value*'
        }

        It 'refuses a registry key path without a hive' {
            { Test-IntuneWin32Rule -KeyPath 'SOFTWARE\X' -RegistryOperation Exists } |
                Should-Throw -ExceptionMessage '*hive*'
        }

        It 'limits the operations and operators' {
            $command = Get-Command Test-IntuneWin32Rule
            $command.Parameters['FileOperation'].Attributes.ValidValues |
                Should-BeCollection @('Exists', 'DoesNotExist', 'Version', 'SizeInMB', 'ModifiedDate',
                    'CreatedDate')
            $command.Parameters['RegistryOperation'].Attributes.ValidValues |
                Should-BeCollection @('Exists', 'DoesNotExist', 'String', 'Integer', 'Version')
        }
    }

    Context 'File rules' {
        It 'is met by a present file and not by a missing one (W32-FILE-EXISTS, W32-FILE-MISSING)' {
            $intuneWin32RuleSplat = @{
                Path             = $script:Fixtures
                FileOrFolderName = 'present.txt'
                FileOperation    = 'Exists'
            }
            $met = Test-IntuneWin32Rule @intuneWin32RuleSplat
            $met.Met | Should-BeTrue
            $met.Kind | Should-Be 'File'
            $met.RuleType | Should-Be 'Detection'
            $met.PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.RuleResult'
            $intuneWin32RuleSplat2 = @{
                Path             = $script:Fixtures
                FileOrFolderName = 'missing.txt'
                FileOperation    = 'Exists'
            }
            $miss = Test-IntuneWin32Rule @intuneWin32RuleSplat2
            $miss.Met | Should-BeFalse
            $miss.Reason | Should-BeLikeString '*does not exist'
        }

        It 'reports DoesNotExist as never met, the way the agent behaves (W32-FILE-NOTEXIST, -FALSE)' {
            $intuneWin32RuleSplat = @{
                Path             = $script:Fixtures
                FileOrFolderName = 'missing.txt'
                FileOperation    = 'DoesNotExist'
            }
            $absent = Test-IntuneWin32Rule @intuneWin32RuleSplat
            $absent.Met | Should-BeFalse
            $absent.Reason | Should-BeLikeString '*absent, but the agent*not met even then*'
            $intuneWin32RuleSplat2 = @{
                Path             = $script:Fixtures
                FileOrFolderName = 'present.txt'
                FileOperation    = 'DoesNotExist'
                RuleType         = 'Requirement'
            }
            $present = Test-IntuneWin32Rule @intuneWin32RuleSplat2
            $present.Met | Should-BeFalse
            $present.Reason | Should-BeLikeString '*requirement rule*invalid rule (0x87D30004*'
        }

        It 'compares the file version as a version (W32-FILE-VER-GE, W32-FILE-VER-LT)' -Skip:(
            -not $script:HasVersioned) {
            $intuneWin32RuleSplat = @{
                Path             = $script:Fixtures
                FileOrFolderName = 'versioned.exe'
                FileOperation    = 'Version'
                Operator         = 'GreaterThanOrEqual'
                Value            = '9.0'
            }
            $ge = Test-IntuneWin32Rule @intuneWin32RuleSplat
            $ge.Met | Should-BeTrue
            $ge.Actual | Should-MatchString '^\d+\.\d+\.\d+\.\d+$'
            $intuneWin32RuleSplat2 = @{
                Path             = $script:Fixtures
                FileOrFolderName = 'versioned.exe'
                FileOperation    = 'Version'
                Operator         = 'LessThan'
                Value            = '9.0'
            }
            (Test-IntuneWin32Rule @intuneWin32RuleSplat2).Met | Should-BeFalse
        }

        It 'is not met by a file without a version resource' {
            $intuneWin32RuleSplat = @{
                Path             = $script:Fixtures
                FileOrFolderName = 'present.txt'
                FileOperation    = 'Version'
                Operator         = 'GreaterThan'
                Value            = '1.0'
            }
            $result = Test-IntuneWin32Rule @intuneWin32RuleSplat
            $result.Met | Should-BeFalse
            $result.Reason | Should-BeLikeString '*no version resource*'
        }

        It 'measures size in whole MiB rounded down (W32-FILE-SIZE-EQ, W32-FILE-SIZE-GT)' {
            $intuneWin32RuleSplat = @{
                Path             = $script:Fixtures
                FileOrFolderName = 'big.bin'
                FileOperation    = 'SizeInMB'
                Operator         = 'Equal'
                Value            = '2'
            }
            $eq = Test-IntuneWin32Rule @intuneWin32RuleSplat
            $eq.Met | Should-BeTrue
            $eq.Actual | Should-Be '2'
            $intuneWin32RuleSplat2 = @{
                Path             = $script:Fixtures
                FileOrFolderName = 'big.bin'
                FileOperation    = 'SizeInMB'
                Operator         = 'GreaterThan'
                Value            = '2'
            }
            (Test-IntuneWin32Rule @intuneWin32RuleSplat2).Met | Should-BeFalse
        }

        It 'compares the modified date in UTC (W32-FILE-DATE-GT, W32-FILE-DATE-LT)' {
            $intuneWin32RuleSplat = @{
                Path             = $script:Fixtures
                FileOrFolderName = 'present.txt'
                FileOperation    = 'ModifiedDate'
                Operator         = 'GreaterThan'
                Value            = '2024-01-01T00:00:00Z'
            }
            $gt = Test-IntuneWin32Rule @intuneWin32RuleSplat
            $gt.Met | Should-BeTrue
            $gt.Actual | Should-BeLikeString '2024-06-15T12:00:00*'
            $intuneWin32RuleSplat2 = @{
                Path             = $script:Fixtures
                FileOrFolderName = 'present.txt'
                FileOperation    = 'ModifiedDate'
                Operator         = 'LessThan'
                Value            = '2024-01-01T00:00:00Z'
            }
            (Test-IntuneWin32Rule @intuneWin32RuleSplat2).Met | Should-BeFalse
        }

        It 'is not met for a comparison on a missing file' {
            $intuneWin32RuleSplat = @{
                Path             = $script:Fixtures
                FileOrFolderName = 'missing.bin'
                FileOperation    = 'SizeInMB'
                Operator         = 'Equal'
                Value            = '2'
            }
            (Test-IntuneWin32Rule @intuneWin32RuleSplat).Reason |
                Should-BeLikeString '*does not exist, so the SizeInMB rule*'
        }

        It 'expands %ProgramFiles% in the 32-bit context with the switch (W32-FILE-PF-32, -64)' -Skip:(
            -not [Environment]::Is64BitOperatingSystem) {
            $intuneWin32RuleSplat = @{
                Path                 = '%ProgramFiles%'
                FileOrFolderName     = 'Common Files'
                FileOperation        = 'Exists'
                Check32BitOn64System = $true
            }
            $result = Test-IntuneWin32Rule @intuneWin32RuleSplat
            $result.Target | Should-Be (Join-Path ${env:ProgramFiles(x86)} 'Common Files')
            $result.Check32BitOn64System | Should-BeTrue
            $intuneWin32RuleSplat2 = @{
                Path             = '%ProgramFiles%'
                FileOrFolderName = 'Common Files'
                FileOperation    = 'Exists'
            }
            $default = Test-IntuneWin32Rule @intuneWin32RuleSplat2
            $default.Target | Should-Be (Join-Path $env:ProgramFiles 'Common Files')
        }
    }

    Context 'Registry rules' {
        It 'tests a key, a value, and their absence (W32-REG-KEY-*, W32-REG-VAL-EXISTS)' {
            (Test-IntuneWin32Rule -KeyPath $script:KeyPath -RegistryOperation Exists).Met | Should-BeTrue
            (Test-IntuneWin32Rule -KeyPath "$($script:KeyPath)\Nope" -RegistryOperation Exists).Met |
                Should-BeFalse
            (Test-IntuneWin32Rule -KeyPath "$($script:KeyPath)\Nope" -RegistryOperation DoesNotExist).Met |
                Should-BeTrue
            (Test-IntuneWin32Rule -KeyPath $script:KeyPath -ValueName Name -RegistryOperation Exists).Met |
                Should-BeTrue
            (Test-IntuneWin32Rule -KeyPath $script:KeyPath -ValueName Nope -RegistryOperation Exists).Met |
                Should-BeFalse
        }

        It 'compares strings case-insensitively (W32-REG-STR-EQ, W32-REG-STR-CASE, W32-REG-STR-NE)' {
            $intuneWin32RuleSplat = @{
                KeyPath           = $script:KeyPath
                ValueName         = 'Name'
                RegistryOperation = 'String'
                Operator          = 'Equal'
                Value             = 'intunescriptlab'
            }
            (Test-IntuneWin32Rule @intuneWin32RuleSplat).Met | Should-BeTrue
            $intuneWin32RuleSplat2 = @{
                KeyPath           = $script:KeyPath
                ValueName         = 'Name'
                RegistryOperation = 'String'
                Operator          = 'Equal'
                Value             = 'other'
            }
            $ne = Test-IntuneWin32Rule @intuneWin32RuleSplat2
            $ne.Met | Should-BeFalse
            $ne.Actual | Should-Be 'IntuneScriptLab'
        }

        It 'compares integers from a DWORD and from a REG_SZ (W32-REG-INT-GT, W32-REG-INT-ONSZ)' {
            $intuneWin32RuleSplat = @{
                KeyPath           = $script:KeyPath
                ValueName         = 'Build'
                RegistryOperation = 'Integer'
                Operator          = 'GreaterThan'
                Value             = '40'
            }
            (Test-IntuneWin32Rule @intuneWin32RuleSplat).Met | Should-BeTrue
            $intuneWin32RuleSplat2 = @{
                KeyPath           = $script:KeyPath
                ValueName         = 'Build'
                RegistryOperation = 'Integer'
                Operator          = 'GreaterThan'
                Value             = '50'
            }
            (Test-IntuneWin32Rule @intuneWin32RuleSplat2).Met | Should-BeFalse
            $intuneWin32RuleSplat3 = @{
                KeyPath           = $script:KeyPath
                ValueName         = 'BuildText'
                RegistryOperation = 'Integer'
                Operator          = 'GreaterThan'
                Value             = '40'
            }
            (Test-IntuneWin32Rule @intuneWin32RuleSplat3).Met | Should-BeTrue
        }

        It 'compares a REG_SZ version as a version (W32-REG-VER-GE, W32-REG-VER-LT)' {
            $intuneWin32RuleSplat = @{
                KeyPath           = $script:KeyPath
                ValueName         = 'Version'
                RegistryOperation = 'Version'
                Operator          = 'GreaterThanOrEqual'
                Value             = '9.0'
            }
            (Test-IntuneWin32Rule @intuneWin32RuleSplat).Met | Should-BeTrue
            $intuneWin32RuleSplat2 = @{
                KeyPath           = $script:KeyPath
                ValueName         = 'Version'
                RegistryOperation = 'Version'
                Operator          = 'LessThan'
                Value             = '9.0'
            }
            (Test-IntuneWin32Rule @intuneWin32RuleSplat2).Met | Should-BeFalse
        }

        It 'is not met when the value is missing, and needs a value name for a comparison' {
            $intuneWin32RuleSplat = @{
                KeyPath           = $script:KeyPath
                ValueName         = 'Nope'
                RegistryOperation = 'String'
                Operator          = 'Equal'
                Value             = 'x'
            }
            (Test-IntuneWin32Rule @intuneWin32RuleSplat).Reason | Should-BeLikeString '*value does not exist*'
            $intuneWin32RuleSplat2 = @{
                KeyPath           = $script:KeyPath
                RegistryOperation = 'String'
                Operator          = 'Equal'
                Value             = 'x'
            }
            { Test-IntuneWin32Rule @intuneWin32RuleSplat2 } | Should-Throw -ExceptionMessage '*-ValueName*'
        }

        It 'reads the 32-bit view with the switch (W32-REG-VIEW-64, W32-REG-VIEW-32)' -Skip:(
            -not [Environment]::Is64BitOperatingSystem) {
            $keyPath = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion'
            $intuneWin32RuleSplat = @{
                KeyPath           = $keyPath
                ValueName         = 'ProgramFilesDir'
                RegistryOperation = 'String'
                Operator          = 'Equal'
                Value             = $env:ProgramFiles
            }
            $view64 = Test-IntuneWin32Rule @intuneWin32RuleSplat
            $view64.Met | Should-BeTrue
            $intuneWin32RuleSplat2 = @{
                KeyPath              = $keyPath
                ValueName            = 'ProgramFilesDir'
                RegistryOperation    = 'String'
                Operator             = 'Equal'
                Value                = ${env:ProgramFiles(x86)}
                Check32BitOn64System = $true
            }
            $view32 = Test-IntuneWin32Rule @intuneWin32RuleSplat2
            $view32.Met | Should-BeTrue
            $view32.Reason | Should-BeLikeString '*32-bit view*'
        }

        It 'accepts the HKLM short form' {
            (Test-IntuneWin32Rule -KeyPath 'HKLM\SOFTWARE\Microsoft' -RegistryOperation Exists).Met | Should-BeTrue
        }
    }

    Context 'Product code rules' {
        It 'is met by an installed product without a version operator (W32-MSI-EXISTS)' {
            $result = Test-IntuneWin32Rule -ProductCode $script:Code
            $result.Met | Should-BeTrue
            $result.Operation | Should-Be 'Exists'
            $result.Actual | Should-Be '110.0.2'
            $result.Reason | Should-BeLikeString 'ISL Test Product 110.0.2 is installed*'
        }

        It 'compares the product version as a version (W32-MSI-VER-GE, W32-MSI-VER-GT-FALSE)' {
            (Test-IntuneWin32Rule -ProductCode $script:Code -Operator GreaterThanOrEqual -Value '99.0.0').Met |
                Should-BeTrue
            (Test-IntuneWin32Rule -ProductCode $script:Code -Operator GreaterThan -Value '200.0.0').Met |
                Should-BeFalse
        }

        It 'is not met by a product that is not installed (W32-MSI-MISSING)' {
            $result = Test-IntuneWin32Rule -ProductCode '{00000000-1111-2222-3333-444444444444}'
            $result.Met | Should-BeFalse
            $result.Actual | Should-Be 'not installed'
        }
    }

    Context 'Rule hashtables' {
        It 'evaluates a Graph-shaped rule and a short one alike' {
            $graph = Test-IntuneWin32Rule -Rule @{
                '@odata.type' = '#microsoft.graph.win32LobAppRegistryRule'; ruleType = 'requirement'
                keyPath = $script:KeyPath; valueName = 'Version'; operationType = 'version'
                operator = 'greaterThanOrEqual'; comparisonValue = '9.0'
            }
            $graph.Met | Should-BeTrue
            $graph.RuleType | Should-Be 'requirement'
            $short = Test-IntuneWin32Rule -Rule @{ Type = 'ProductCode'; ProductCode = $script:Code }
            $short.Met | Should-BeTrue
            $short.Kind | Should-Be 'ProductCode'
        }

        It 'keeps the -RuleType given when the hashtable has none' {
            (Test-IntuneWin32Rule -RuleType Requirement -Rule @{
                Type = 'File'; Path = $script:Fixtures; FileOrFolderName = 'present.txt'; OperationType = 'exists'
            }).RuleType | Should-Be 'Requirement'
        }
    }
}
