#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    What -WhatIf, and a WhatIf preference in the caller's session, do across the module. A command
    that starts a script or writes a report previews it: it says what it would do, does none of it
    and returns nothing. The scripts here leave a marker file when they run, so that "did not run"
    is checked on the disk and not on a mock.

    The preference used to reach the cmdlets inside the harness instead. The copy of the script
    was skipped, the host was started on a file that was not there, and its complaint came back as
    the result of the script (#88).
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }
    . (Join-Path $script:ModuleRoot 'Tests\TestHelpers\TestHelpers.ps1')

    function New-MarkerScript {
        <#
        .SYNOPSIS
            Writes a script that leaves a marker file, writes a line and exits 0. Returns both paths.
        #>
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Writes one script under TestDrive.')]
        [CmdletBinding()]
        [OutputType([System.Management.Automation.PSCustomObject])]
        param(
            [Parameter(Mandatory)]
            [string]$Name
        )

        $marker = Join-Path $TestDrive "$Name.marker"
        $body = "Set-Content -LiteralPath '$marker' -Value 'ran'`r`nWrite-Output 'present'`r`nexit 0"
        [pscustomobject]@{
            Script = New-TestScript "$Name\Detect.ps1" $body -Bom
            Marker = $marker
        }
    }
}

Describe 'What -WhatIf does across the module' -Tag 'Unit', 'Contract' {

    Context 'The fixture' {
        It 'leaves its marker when the script does run' {
            $probe = New-MarkerScript -Name 'Sanity'
            $result = Invoke-IntuneDetectionTest -Path $probe.Script -TimeoutSeconds 60

            $result.Detected | Should-BeTrue
            Test-Path -LiteralPath $probe.Marker | Should-BeTrue
        }
    }

    Context 'Commands that start a script' {
        It 'previews a detection: runs nothing and returns nothing' {
            $probe = New-MarkerScript -Name 'Detection'
            $result = @(Invoke-IntuneDetectionTest -Path $probe.Script -WhatIf)

            $result.Count | Should-Be 0
            Test-Path -LiteralPath $probe.Marker | Should-BeFalse
        }

        It 'previews each script that arrives on the pipeline' {
            $first = New-MarkerScript -Name 'PipelineOne'
            $second = New-MarkerScript -Name 'PipelineTwo'
            $result = @($first.Script, $second.Script | Invoke-IntuneDetectionTest -WhatIf)

            $result.Count | Should-Be 0
            Test-Path -LiteralPath $first.Marker | Should-BeFalse
            Test-Path -LiteralPath $second.Marker | Should-BeFalse
        }

        It 'previews a platform script' {
            $probe = New-MarkerScript -Name 'Platform'
            $result = @(Invoke-IntunePlatformScriptTest -Path $probe.Script -WhatIf)

            $result.Count | Should-Be 0
            Test-Path -LiteralPath $probe.Marker | Should-BeFalse
        }

        It 'previews a requirement script' {
            $probe = New-MarkerScript -Name 'Requirement'
            $requirementSplat = @{ Path = $probe.Script; OutputType = 'String'; Value = 'present' }
            $result = @(Invoke-IntuneRequirementTest @requirementSplat -WhatIf)

            $result.Count | Should-Be 0
            Test-Path -LiteralPath $probe.Marker | Should-BeFalse
        }

        It 'previews a remediation: neither the detection nor the remediation runs' {
            $detection = New-MarkerScript -Name 'RemediationDetect'
            $remediation = New-MarkerScript -Name 'RemediationFix'
            $remediationSplat = @{ DetectionPath = $detection.Script; RemediationPath = $remediation.Script }
            $result = @(Invoke-IntuneRemediationTest @remediationSplat -WhatIf)

            $result.Count | Should-Be 0
            Test-Path -LiteralPath $detection.Marker | Should-BeFalse
            Test-Path -LiteralPath $remediation.Marker | Should-BeFalse
        }

        It 'previews a Win32 app flow: neither the detection nor the install command runs' {
            $detection = New-MarkerScript -Name 'AppDetect'
            $content = Join-Path $TestDrive 'AppContent'
            $null = New-Item -ItemType Directory -Path $content -Force
            $installed = Join-Path $TestDrive 'App.installed'
            $appSplat = @{
                DetectionPath = $detection.Script
                ContentPath = $content
                InstallCommand = "cmd.exe /c echo installed > `"$installed`""
            }
            $result = @(Invoke-IntuneWin32AppTest @appSplat -WhatIf)

            $result.Count | Should-Be 0
            Test-Path -LiteralPath $detection.Marker | Should-BeFalse
            Test-Path -LiteralPath $installed | Should-BeFalse
        }
    }

    Context 'Commands that write a report' {
        It 'previews the diagnostic package: no zip and no result' {
            $logs = Join-Path $TestDrive 'NoLogs'
            $null = New-Item -ItemType Directory -Path $logs -Force
            $zip = Join-Path $TestDrive 'preview.zip'
            $result = @(Export-IntuneAgentDiagnostic -Path $zip -LogPath $logs -SkipRegistry -WhatIf)

            $result.Count | Should-Be 0
            Test-Path -LiteralPath $zip | Should-BeFalse
        }

        It 'previews the SARIF log: no file and no result' {
            $script = New-TestScript 'Sarif\Detect.ps1' "Write-Output 'present'`r`nreturn`r`nexit 0" -Bom
            $findings = @(Test-IntuneScript -Path $script -ScriptType Detection)
            $sarif = Join-Path $TestDrive 'preview.sarif'
            $result = @($findings | Export-IntuneFindingSarif -Path $sarif -Root $TestDrive -WhatIf)

            $findings.Count | Should-BeGreaterThan 0
            $result.Count | Should-Be 0
            Test-Path -LiteralPath $sarif | Should-BeFalse
        }
    }

    Context 'A WhatIf preference in the caller''s session' {
        It 'previews the run as -WhatIf does, and does not start the host on a missing copy' {
            $probe = New-MarkerScript -Name 'Preference'
            $run = Invoke-CallerScript -Statement @(
                "`$WhatIfPreference = `$true"
                "`$results = @(Invoke-IntuneDetectionTest -Path '$($probe.Script)')"
                "'results: ' + `$results.Count"
            )

            $run.ReachedEnd | Should-BeTrue
            @($run.Output | Where-Object { $_ -like 'What if:*' }) | Should-BeCollection -Count 1
            @($run.Output | Where-Object { $_ -like 'results:*' }) | Should-BeCollection @('results: 0')
            $run.ErrorId | Should-BeCollection -Count 0
            Test-Path -LiteralPath $probe.Marker | Should-BeFalse
        }

        It 'does not reach a command that only reads: the analysis is the same' {
            $script = New-TestScript 'Analysis\Detect.ps1' "Write-Output 'present'`r`nreturn`r`nexit 0" -Bom
            $expected = @(Test-IntuneScript -Path $script -ScriptType Detection)
            $underPreference = @(InModuleScope IntuneScriptLab -Parameters @{ Path = $script } {
                    $WhatIfPreference = $true
                    Test-IntuneScript -Path $Path -ScriptType Detection
                })

            $expected.Count | Should-BeGreaterThan 0
            @($underPreference.RuleName | Sort-Object) | Should-BeCollection @($expected.RuleName | Sort-Object)
        }
    }
}
