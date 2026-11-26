#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The public analyzer surface: how a script's type is resolved and announced, folder and
    pipeline input, and the rule and severity filters. The rules themselves are tested one per
    file under Tests\Unit\Private\Rules.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    # The module this tree holds, imported once for the run: a copy installed from the Gallery
    # would otherwise be tested in its place
    $loaded = Get-Module -Name IntuneScriptLab
    if (-not $loaded -or $loaded.ModuleBase -ne $script:ModuleRoot) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force
    }
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')
}

Describe 'Test-IntuneScript' -Tag 'Unit', 'Public' {

    Context 'Parameter Validation' {
        It 'takes paths and FileInfo objects from the pipeline' {
            New-TestScript 'a\Detect-A.ps1' 'exit 2' | Out-Null
            $folder = Join-Path $TestDrive 'a'
            @(Get-ChildItem $folder | Test-IntuneScript -IncludeRule IslExitCodeIssue).Count |
                Should-BeGreaterThan 0
            @("$folder\Detect-A.ps1" | Test-IntuneScript -IncludeRule IslExitCodeIssue).Count |
                Should-BeGreaterThan 0
        }

        It 'expands a folder to every .ps1 below it' {
            New-TestScript 'tree\one\Detect-One.ps1' 'exit 2' | Out-Null
            New-TestScript 'tree\two\Detect-Two.ps1' 'exit 2' | Out-Null
            $findings = @(Test-IntuneScript -Path (Join-Path $TestDrive 'tree') -IncludeRule IslExitCodeIssue)
            @($findings.ScriptPath | Sort-Object -Unique).Count | Should-Be 2
        }

        It 'reports a path that does not exist and still analyzes the others' {
            $good = New-TestScript 'mix\Detect-Good.ps1' 'exit 2'
            $missing = Join-Path $TestDrive 'missing.ps1'
            $analysisSplat = @{
                Path = $missing, $good; IncludeRule = 'IslExitCodeIssue'; ErrorAction = 'Continue'
            }

            $output = Test-IntuneScript @analysisSplat 2>&1
            $errors = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $findings = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })

            $errors | Should-BeCollection -Count 1
            $errors[0].FullyQualifiedErrorId | Should-BeLikeString 'PathNotFound,*'
            $findings.Count | Should-BeGreaterThan 0
            @($findings.ScriptPath | Sort-Object -Unique) | Should-BeCollection @($good)
        }

        It 'leaves one record in a caller''s -ErrorVariable for a path that does not exist' {
            $missing = Join-Path $TestDrive 'missing-once.ps1'

            $null = Test-IntuneScript -Path $missing -ErrorVariable collected -ErrorAction SilentlyContinue

            @($collected) | Should-BeCollection -Count 1
            $collected[0].FullyQualifiedErrorId | Should-BeLikeString 'PathNotFound,Test-IntuneScript'
        }

        It 'ends at a path that does not exist when the caller asks it to stop' {
            { Test-IntuneScript -Path (Join-Path $TestDrive 'missing.ps1') -ErrorAction Stop } |
                Should-Throw -FullyQualifiedErrorId 'PathNotFound,*'
        }

        It 'reports a script whose settings file is wrong and still analyzes a script elsewhere' {
            $broken = New-TestScript 'badsettings\Detect-One.ps1' 'exit 2'
            $settingsFile = Join-Path (Split-Path $broken -Parent) 'IntuneScriptLab.settings.psd1'
            Set-Content -LiteralPath $settingsFile -Value "@{ MinimumSeverity = 'Fatal' }" -Encoding ascii
            $good = New-TestScript 'goodsettings\Detect-Two.ps1' 'exit 2'
            $analysisSplat = @{ Path = $broken, $good; IncludeRule = 'IslExitCodeIssue'; ErrorAction = 'Continue' }

            $output = Test-IntuneScript @analysisSplat 2>&1
            $errors = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $findings = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })

            $errors | Should-BeCollection -Count 1
            $errors[0].FullyQualifiedErrorId | Should-BeLikeString 'SettingsInvalid*'
            $errors[0].Exception.Message | Should-BeLikeString '*MinimumSeverity must be one of*'
            @($findings.ScriptPath | Sort-Object -Unique) | Should-BeCollection @($good)
        }

        It 'ends before any script is analyzed when -Settings itself is wrong' {
            $one = New-TestScript 'given\Detect-One.ps1' 'exit 2'
            $two = New-TestScript 'given\Detect-Two.ps1' 'exit 2'
            Mock Get-IslScriptContext -ModuleName IntuneScriptLab { }

            { Test-IntuneScript -Path $one, $two -Settings @{ MinimumSeverity = 'Fatal' } } |
                Should-Throw -FullyQualifiedErrorId 'SettingsInvalid*'
            Should-Invoke Get-IslScriptContext -ModuleName IntuneScriptLab -Times 0 -Exactly
        }

        It 'reports a settings file whose Severity is not a hashtable with SettingsInvalid, naming the file' {
            $scriptPath = New-TestScript 'severitytext\Detect-One.ps1' 'exit 2'
            $settingsFile = Join-Path (Split-Path $scriptPath -Parent) 'IntuneScriptLab.settings.psd1'
            Set-Content -LiteralPath $settingsFile -Value "@{ Severity = 'Error' }" -Encoding ascii

            $output = Test-IntuneScript -Path $scriptPath -ErrorAction Continue 2>&1
            $errors = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })

            $errors | Should-BeCollection -Count 1
            $errors[0].FullyQualifiedErrorId | Should-BeLikeString 'SettingsInvalid*'
            $errors[0].Exception.Message | Should-BeLikeString "$settingsFile*Severity must be a hashtable*"
        }

        It 'leaves a calling script one error for a path that is not there, and the findings of the other' {
            $good = New-TestScript 'caller\Detect-Good.ps1' 'exit 2'
            $missing = Join-Path $TestDrive 'caller\missing.ps1'

            $run = Invoke-CallerScript -Statement @(
                "`$findings = @(Test-IntuneScript -Path '$missing', '$good' -IncludeRule IslExitCodeIssue)"
                "'analyzed: ' + @(`$findings.ScriptPath | Sort-Object -Unique).Count"
            )

            $run.ReachedEnd | Should-BeTrue
            $run.Output | Should-BeCollection @('analyzed: 1')
            $run.ErrorId | Should-BeCollection -Count 1
            $run.ErrorId[0] | Should-BeLikeString 'PathNotFound,*'
        }
    }

    Context 'Core Functionality' {
        It 'infers Detection from the file name and says so' {
            $path = New-TestScript 'Detect-Thing.ps1' 'Write-Host "x"; exit 0'
            $findings = @(Test-IntuneScript -Path $path)
            $findings.ScriptType | Should-All { $_ -eq 'Detection' }
            @($findings | Where-Object RuleName -eq 'IslAssumedContext').Count | Should-Be 1
            @($findings | Where-Object RuleName -eq 'IslOutputIssue').Count | Should-BeGreaterThan 0
        }

        It 'emits the assumed-context note even when nothing else is found' {
            $path = New-TestScript 'Detect-Clean.ps1' "Write-Output 'checked'`nexit 0"
            @(Test-IntuneScript -Path $path).RuleName | Should-BeCollection @('IslAssumedContext')
        }

        It 'tells a user-context script that Entra-registered devices skip it' {
            $path = New-TestScript 'Configure-Clean.ps1' 'Write-Output "hello"'
            $findings = @(Test-IntuneScript -Path $path)
            $findings.RuleName | Should-BeCollection @('IslAssumedContext', 'IslContextIssue')
            $findings[1].Message | Should-BeLikeString '*Entra-registered*'
            @(Test-IntuneScript -Path $path -Context System).RuleName | Should-BeCollection @('IslAssumedContext')
        }

        It 'infers a Win32 detection from the folder, so the Win32-only rules apply' {
            $body = "if (Test-Path 'C:\agent.exe') { exit 0 } else { exit 1 }"
            $path = New-TestScript 'Win32\Agent\Detect.ps1' $body
            $findings = @(Test-IntuneScript -Path $path)
            $findings.ScriptType | Should-All { $_ -eq 'Win32Detection' }
            @($findings | Where-Object { $_.RuleName -eq 'IslOutputIssue' -and $_.Severity -eq 'Error' }).Count |
                Should-Be 1
        }

        It 'lets a directive comment override the file name, and treats it as declared' {
            $path = New-TestScript 'script.ps1' "# IntuneScriptLab: ScriptType=Win32Detection`nexit 0"
            $findings = @(Test-IntuneScript -Path $path)
            $findings.ScriptType | Should-All { $_ -eq 'Win32Detection' }
            # A type written in the script is not assumed, so the note stays away
            @($findings | Where-Object RuleName -eq 'IslAssumedContext').Count | Should-Be 0
        }

        It 'lets an explicit parameter override both, and drops the note' {
            # An unhandled throw yields a finding for every type, so the type stamp is observable
            $path = New-TestScript 'Detect-Thing.ps1' "# IntuneScriptLab: ScriptType=Win32Detection`nthrow 'x'"
            $findings = @(Test-IntuneScript -Path $path -ScriptType Remediation)
            $findings.Count | Should-BeGreaterThan 0
            $findings.ScriptType | Should-All { $_ -eq 'Remediation' }
            @($findings | Where-Object RuleName -eq 'IslAssumedContext').Count | Should-Be 0
        }

        It 'returns IntuneScriptLab.Finding objects with the documented properties' {
            $path = New-TestScript 'Detect-Shape.ps1' 'exit 2'
            $finding = @(Test-IntuneScript -Path $path -IncludeRule IslExitCodeIssue)[0]
            $finding.PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.Finding'
            $finding.PSObject.Properties.Name | Should-BeCollection @(
                'RuleName', 'Severity', 'Message', 'ScriptPath', 'Line', 'Column', 'ScriptType', 'Text', 'Evidence'
                'Suppressed', 'Fix'
            )
            $finding.Suppressed | Should-BeFalse
        }
    }

    Context 'Filtering' {
        It 'filters by minimum severity, including the assumed-context note' {
            $path = New-TestScript 'Detect-Sev.ps1' 'Write-Host "a"; exit 2'
            @(Test-IntuneScript -Path $path -MinimumSeverity Error).Count | Should-Be 0
            $warnings = @(Test-IntuneScript -Path $path -MinimumSeverity Warning)
            @($warnings | Where-Object RuleName -eq 'IslAssumedContext').Count | Should-Be 0
            $warnings.Count | Should-BeGreaterThan 0
        }

        It 'includes and excludes rules by wildcard' {
            $path = New-TestScript 'Detect-Rules.ps1' 'Write-Host "a"; exit 2'
            $excluded = @(Test-IntuneScript -Path $path -ExcludeRule 'IslOutput*', 'IslExit*')
            @($excluded | Where-Object { $_.RuleName -like 'IslOutput*' -or $_.RuleName -like 'IslExit*' }).Count |
                Should-Be 0
            $included = @(Test-IntuneScript -Path $path -IncludeRule 'IslExit*' -MinimumSeverity Warning)
            $included.RuleName | Should-All { $_ -eq 'IslExitCodeIssue' }
        }

        It 'applies the rule filters to the assumed-context note as well' {
            $path = New-TestScript 'Detect-Note.ps1' 'Write-Host "a"; exit 2'
            @(Test-IntuneScript -Path $path -ExcludeRule IslAssumedContext).RuleName |
                Should-NotContainCollection 'IslAssumedContext'
            @(Test-IntuneScript -Path $path -IncludeRule 'IslExit*').RuleName |
                Should-All { $_ -eq 'IslExitCodeIssue' }
            @(Test-IntuneScript -Path $path -IncludeRule 'IslAssumed*').RuleName |
                Should-BeCollection @('IslAssumedContext')
        }
    }

    Context 'Suppressions' {
        It 'drops a finding a header directive suppresses, and shows it with -IncludeSuppressed' {
            $body = "# IntuneScriptLab: ScriptType=Detection Suppress=IslLongSleep`n" +
            "Start-Sleep -Seconds 4000`nRead-Host 'Continue?'`nexit 1"
            $path = New-TestScript 'Detect-Quiet.ps1' $body
            @(Test-IntuneScript -Path $path).RuleName | Should-NotContainCollection 'IslLongSleep'
            $all = @(Test-IntuneScript -Path $path -IncludeSuppressed)
            $sleep = @($all | Where-Object RuleName -eq 'IslLongSleep')
            $sleep.Count | Should-Be 1
            $sleep[0].Suppressed | Should-BeTrue
            @($all | Where-Object { -not $_.Suppressed }).Count | Should-BeGreaterThan 0
        }

        It 'suppresses only the line a trailing or preceding directive names' {
            $body = @(
                '# IntuneScriptLab: ScriptType=Detection'
                'Start-Sleep -Seconds 4000   # IntuneScriptLab: Suppress=IslLongSleep'
                'Start-Sleep -Seconds 5000'
                '# IntuneScriptLab: Suppress=IslLong*'
                'Start-Sleep -Seconds 6000'
                'exit 1'
            ) -join "`n"
            $path = New-TestScript 'Detect-Lines.ps1' $body
            $sleeps = @(Test-IntuneScript -Path $path -IncludeRule IslLongSleep)
            $sleeps.Line | Should-BeCollection @(3)
        }
    }

    Context 'Settings file' {
        BeforeAll {
            $script:Repo = Join-Path $TestDrive 'settings-repo'
            $null = New-Item -ItemType Directory -Path (Join-Path $script:Repo 'Scripts') -Force
            @(
                '@{'
                "    ExcludeRule = @('IslAssumedContext')"
                "    Severity = @{ IslLongSleep = 'Information' }"
                "    ScriptType = 'Win32Detection'"
                "    Context = 'System'"
                "    Architecture = 'x64'"
                '}'
            ) -join "`n" | Set-Content (Join-Path $script:Repo 'IntuneScriptLab.settings.psd1')
            $script:Slow = Join-Path $script:Repo 'Scripts\run.ps1'
            [System.IO.File]::WriteAllText($script:Slow, "Start-Sleep -Seconds 4000`nWrite-Output 'x'`nexit 0",
                [System.Text.UTF8Encoding]::new($true))
        }

        It 'applies the nearest settings file: exclusions, severity overrides and the type' {
            $findings = @(Test-IntuneScript -Path $script:Slow)
            $findings.RuleName | Should-NotContainCollection 'IslAssumedContext'
            $findings.ScriptType | Should-All { $_ -eq 'Win32Detection' }
            $sleep = @($findings | Where-Object RuleName -eq 'IslLongSleep')
            $sleep.Count | Should-Be 1
            $sleep[0].Severity | Should-Be 'Information'
        }

        It 'lets parameters and directives win over the settings file' {
            @(Test-IntuneScript -Path $script:Slow -ScriptType Remediation).ScriptType |
                Should-All { $_ -eq 'Remediation' }
            $withDirective = Join-Path $script:Repo 'Scripts\directive.ps1'
            Set-Content $withDirective "# IntuneScriptLab: ScriptType=PlatformScript`nRead-Host 'x'`nexit 0"
            @(Test-IntuneScript -Path $withDirective -IncludeSuppressed).ScriptType |
                Should-All { $_ -eq 'PlatformScript' }
            # Each finding's rule: the call can return none, and an empty array has no RuleName
            @(Test-IntuneScript -Path $script:Slow -MinimumSeverity Warning | ForEach-Object { $_.RuleName }) |
                Should-NotContainCollection 'IslLongSleep'
        }

        It 'lets an explicit -IncludeRule set the file''s exclusions aside, while -ExcludeRule adds to them' {
            $settings = @{ ExcludeRule = 'IslLongSleep' }
            $asked = @(Test-IntuneScript -Path $script:Slow -Settings $settings -IncludeRule IslLongSleep)
            $asked.RuleName | Should-ContainCollection 'IslLongSleep'
            $added = @(Test-IntuneScript -Path $script:Slow -Settings $settings -ExcludeRule IslAssumedContext)
            $added.RuleName | Should-NotContainCollection 'IslLongSleep'
            $added.RuleName | Should-NotContainCollection 'IslAssumedContext'
        }

        It 'takes -Settings as a path or a hashtable, and @{} as no settings' {
            $explicit = @(Test-IntuneScript -Path $script:Slow -Settings @{ ExcludeRule = 'IslLongSleep' })
            $explicit.RuleName | Should-NotContainCollection 'IslLongSleep'
            $explicit.RuleName | Should-ContainCollection 'IslAssumedContext'
            $none = @(Test-IntuneScript -Path $script:Slow -Settings @{})
            $none.RuleName | Should-ContainCollection 'IslAssumedContext'
            @($none | Where-Object RuleName -eq 'IslLongSleep')[0].Severity | Should-Be 'Error'
            $file = Join-Path $script:Repo 'IntuneScriptLab.settings.psd1'
            @(Test-IntuneScript -Path $script:Slow -Settings $file).RuleName |
                Should-NotContainCollection 'IslAssumedContext'
        }
    }

    Context 'The help example that gates a build' {
        BeforeAll {
            # Example 3 of the help, as written there, run as a script in a new process
            $script:GateExample = @(
                "`$ErrorActionPreference = 'Stop'"
                '$findings = @(Get-ChildItem .\Remediations -Recurse -Filter *.ps1 |'
                '    Test-IntuneScript -MinimumSeverity Warning -ErrorAction Stop)'
                'if ($findings.Count -gt 0) { exit 1 }'
            )

            function script:Invoke-GateExample {
                <#
                .SYNOPSIS
                    Runs the gate example of the help as a script in a new process from a folder.

                .DESCRIPTION
                    Puts a Set-Location to the folder before the statements in $script:GateExample
                    and runs them with Invoke-CallerScript, as a script without a try runs them.

                .PARAMETER Folder
                    The folder the script runs in, which holds the Remediations folder.

                .EXAMPLE
                    Invoke-GateExample -Folder $folder

                    Runs the example against the scripts below $folder and returns what the script did.

                .INPUTS
                    None.

                .OUTPUTS
                    IntuneScriptLab.Test.CallerScriptResult. Output, ErrorId, ReachedEnd and ExitCode.
                #>
                [CmdletBinding()]
                [OutputType('IntuneScriptLab.Test.CallerScriptResult')]
                param(
                    [string]$Folder
                )

                Invoke-CallerScript -Statement (@("Set-Location -LiteralPath '$Folder'") + $script:GateExample)
            }
        }

        It 'passes a folder whose scripts have no finding at Warning or above' {
            $folder = Join-Path $TestDrive 'gate-clean'
            $null = New-TestScript 'gate-clean\Remediations\A\Detect.ps1' (
                "if (Test-Path 'C:\x') { Write-Output 'ok'; exit 0 } else { Write-Output 'missing'; exit 1 }")

            $run = Invoke-GateExample -Folder $folder

            $run.ReachedEnd | Should-BeTrue
            $run.ExitCode | Should-Be 0
        }

        It 'fails the step on a finding' {
            $folder = Join-Path $TestDrive 'gate-finding'
            $null = New-TestScript 'gate-finding\Remediations\A\Detect.ps1' "Read-Host 'x'`nexit 1"

            $run = Invoke-GateExample -Folder $folder

            $run.ReachedEnd | Should-BeFalse
            $run.ExitCode | Should-Be 1
        }

        It 'fails the step on a script it cannot analyze, instead of passing on the others' {
            $folder = Join-Path $TestDrive 'gate-unreadable'
            $null = New-TestScript 'gate-unreadable\Remediations\A\Detect.ps1' (
                "if (Test-Path 'C:\x') { Write-Output 'ok'; exit 0 } else { Write-Output 'missing'; exit 1 }")
            $settings = Join-Path $folder 'Remediations\A\IntuneScriptLab.settings.psd1'
            Set-Content -LiteralPath $settings -Value "@{ MinimumSeverity = 'Fatal' }" -Encoding ascii

            $run = Invoke-GateExample -Folder $folder

            $run.ReachedEnd | Should-BeFalse
            $run.ExitCode | Should-Be 1
        }
    }
}
