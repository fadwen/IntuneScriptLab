#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Drift between a fake tenant (the Graph seam mocked) and a local folder laid out by the
    convention: byte-identical scripts, a BOM difference, a line-ending difference, a whitespace-only
    difference, a content difference with its first line, a missing local file, an ambiguous match,
    a local file the tenant has no script for, -Map entries and a settings directive that disagrees
    with the policy.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1') -Force

    function script:Get-ByteArray {
        param([string]$Text, [switch]$Bom)
        $preamble = [System.Text.UTF8Encoding]::new([bool]$Bom).GetPreamble()
        [byte[]]($preamble + [System.Text.Encoding]::UTF8.GetBytes($Text))
    }
    function script:ConvertTo-Base64 {
        param([string]$Text, [switch]$Bom)
        [System.Convert]::ToBase64String((Get-ByteArray -Text $Text -Bom:$Bom))
    }
    function script:Write-Local {
        param([string]$RelativePath, [string]$Text, [switch]$Bom)
        $full = Join-Path $script:Root $RelativePath
        $null = New-Item -ItemType Directory -Path (Split-Path $full -Parent) -Force
        [System.IO.File]::WriteAllBytes($full, (Get-ByteArray -Text $Text -Bom:$Bom))
        $full
    }
    # One result of a run, by policy name and role
    function script:Get-Result {
        param($Results, [string]$Policy, [string]$Role)
        $Results | Where-Object { $_.PolicyName -eq $Policy -and $_.Role -eq $Role }
    }

    $script:Detect = "if (Test-Path C:\x) { exit 1 }`r`nexit 0"
    $script:Remediate = "Remove-Item C:\x`r`nexit 0"
    $script:Wallpaper = "Set-ItemProperty HKCU:\Control` Panel\Desktop Wallpaper C:\w.jpg`r`nexit 0"
    $script:AppDetect = "if (Test-Path C:\Widget\widget.exe) { 'installed' }`r`nexit 0"
    $script:Requirement = "if ((Get-CimInstance Win32_OperatingSystem).BuildNumber -ge 26100) { 'ok' }`r`nexit 0"
    $script:DirectiveDetect = "# IntuneScriptLab: Context=User`r`n$($script:Detect)"

    $script:Tenant = @{
        remediations    = @(
            @{ id = 'rem-a'; displayName = 'Fix-Widget'; runAsAccount = 'system'; runAs32Bit = $false
                enforceSignatureCheck = $false; lastModifiedDateTime = '2026-09-20T10:00:00Z'
                detectionScriptContent = ConvertTo-Base64 $script:Detect -Bom
                remediationScriptContent = ConvertTo-Base64 $script:Remediate -Bom }
            @{ id = 'rem-b'; displayName = 'Report-Only'; runAsAccount = 'system'; runAs32Bit = $false
                enforceSignatureCheck = $false; detectionScriptContent = ConvertTo-Base64 $script:Detect -Bom
                remediationScriptContent = $null }
            @{ id = 'rem-c'; displayName = 'Ctx-Check'; runAsAccount = 'system'; runAs32Bit = $false
                enforceSignatureCheck = $false
                detectionScriptContent = ConvertTo-Base64 $script:DirectiveDetect -Bom
                remediationScriptContent = $null }
        )
        platformScripts = @(
            @{ id = 'ps-a'; displayName = 'Set-Wallpaper'; runAsAccount = 'user'; runAs32Bit = $true
                enforceSignatureCheck = $false; scriptContent = ConvertTo-Base64 $script:Wallpaper -Bom }
            @{ id = 'ps-b'; displayName = 'Dup'; runAsAccount = 'system'; runAs32Bit = $false
                enforceSignatureCheck = $false; scriptContent = ConvertTo-Base64 $script:Wallpaper -Bom }
        )
        apps            = @(
            @{
                id = 'app-a'; displayName = 'Widget: 2.0'; lastModifiedDateTime = '2026-09-21T10:00:00Z'
                detectionRules = @(
                    @{ '@odata.type' = '#microsoft.graph.win32LobAppPowerShellScriptDetection'
                        scriptContent = ConvertTo-Base64 $script:AppDetect -Bom
                        enforceSignatureCheck = $false; runAs32Bit = $false }
                )
                requirementRules = @(
                    @{ '@odata.type' = '#microsoft.graph.win32LobAppPowerShellScriptRequirement'
                        scriptContent = ConvertTo-Base64 $script:Requirement -Bom
                        runAsAccount = 'system'; runAs32Bit = $false; enforceSignatureCheck = $false }
                )
            }
            @{
                id = 'app-b'; displayName = 'Widget 1.0'
                detectionRules = @(
                    @{ '@odata.type' = '#microsoft.graph.win32LobAppRegistryDetection'; detectionType = 'exists' }
                )
                requirementRules = @()
            }
        )
    }
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
}

Describe 'Compare-IntuneDeployedScript' -Tag 'Unit', 'Public' {

    BeforeAll {
        $script:Root = Join-Path $TestDrive 'repo'
        # Byte-identical detection; remediation with a content change and no BOM
        Write-Local 'Remediations\Fix-Widget\Detect.ps1' $script:Detect -Bom
        Write-Local 'Remediations\Fix-Widget\Remediate.ps1' "Remove-Item C:\x -Force`r`nexit 0"
        # Report-Only has a local remediation the tenant does not carry, and no detection
        Write-Local 'Remediations\Report-Only\Remediate.ps1' $script:Remediate -Bom
        # Same bytes as the tenant plus a directive that disagrees with the policy
        Write-Local 'Remediations\Ctx-Check\Detect.ps1' $script:DirectiveDetect -Bom
        # LF instead of CRLF, same BOM
        Write-Local 'Scripts\Set-Wallpaper.ps1' ($script:Wallpaper -replace "`r`n", "`n") -Bom
        # Two candidates for Dup: a file named after it and a folder with one script
        Write-Local 'Scripts\Dup.ps1' $script:Wallpaper -Bom
        Write-Local 'Scripts\Dup\run.ps1' $script:Wallpaper -Bom
        # The app's colon becomes an underscore in the folder name; requirement differs by trailing whitespace only
        Write-Local 'Apps\Widget_ 2.0\Detect.ps1' $script:AppDetect -Bom
        Write-Local 'Apps\Widget_ 2.0\Requirement.ps1' ($script:Requirement -replace "'ok' \}", "'ok' }   ") -Bom

        # A mock body sees the test file's script scope, so the fake tenant is read from there
        Mock Invoke-IslGraphRequest -ModuleName IntuneScriptLab {
            $tenant = $script:Tenant
            $summary = {
                param($items)
                @($items | ForEach-Object { @{ id = $_.id; displayName = $_.displayName } })
            }
            switch -Regex ($Uri) {
                '^/beta/deviceManagement/deviceHealthScripts\?' { & $summary $tenant.remediations }
                '^/beta/deviceManagement/deviceHealthScripts/([^?]+)' {
                    $tenant.remediations | Where-Object id -eq $Matches[1]
                }
                '^/beta/deviceManagement/deviceManagementScripts\?' { & $summary $tenant.platformScripts }
                '^/beta/deviceManagement/deviceManagementScripts/([^?]+)' {
                    $tenant.platformScripts | Where-Object id -eq $Matches[1]
                }
                '^/beta/deviceAppManagement/mobileApps\?' { & $summary $tenant.apps }
                '^/beta/deviceAppManagement/mobileApps/([^?]+)' { $tenant.apps | Where-Object id -eq $Matches[1] }
                default { throw "unexpected uri $Uri" }
            }
        }
    }

    Context 'Core Functionality' {
        BeforeAll {
            $script:Results = @(Compare-IntuneDeployedScript -Path $script:Root)
        }

        It 'returns one typed result per script role with both hashes' {
            $script:Results.Count | Should-BeGreaterThan 6
            $script:Results[0].PSObject.TypeNames | Should-ContainCollection 'IntuneScriptLab.DriftResult'
            $detect = Get-Result -Results $script:Results -Policy 'Fix-Widget' -Role 'detection'
            $detect.State | Should-Be 'InSync'
            @($detect.Differences).Count | Should-Be 0
            $detect.LocalHash | Should-Be $detect.TenantHash
            $detect.LocalHash.Length | Should-Be 12
            $detect.Kind | Should-Be 'Remediation'
            $detect.PolicyId | Should-Be 'rem-a'
            $detect.TenantModified | Should-Be '2026-09-20T10:00:00Z'
            $detect.LocalPath | Should-BeLikeString '*Fix-Widget\Detect.ps1'
        }

        It 'reports a content change with its first differing line, and the BOM separately' {
            $remediate = Get-Result -Results $script:Results -Policy 'Fix-Widget' -Role 'remediation'
            $remediate.State | Should-Be 'Drifted'
            @($remediate.Differences | Sort-Object) | Should-BeCollection @('Bom', 'Content')
            $remediate.Detail | Should-BeLikeString "*differs from line 1: local 'Remove-Item C:\x -Force'*"
            $remediate.Detail | Should-BeLikeString '*1 line(s) only local, 1 only in the tenant*'
            $remediate.Detail | Should-BeLikeString "*local file has no BOM, the tenant's has one*"
            $remediate.LocalHash | Should-NotBe $remediate.TenantHash
        }

        It 'reports a line-ending difference on its own' {
            $wallpaper = $script:Results | Where-Object PolicyName -eq 'Set-Wallpaper'
            $wallpaper.Role | Should-Be 'script'
            $wallpaper.State | Should-Be 'Drifted'
            @($wallpaper.Differences) | Should-BeCollection @('LineEndings')
            $wallpaper.Detail | Should-Be 'line endings LF locally, CRLF in the tenant'
        }

        It 'reports trailing whitespace on its own, and matches folder names with underscores' {
            $requirement = Get-Result -Results $script:Results -Policy 'Widget: 2.0' -Role 'requirement'
            $requirement.State | Should-Be 'Drifted'
            @($requirement.Differences) | Should-BeCollection @('Whitespace')
            $requirement.LocalPath | Should-BeLikeString '*Widget_ 2.0\Requirement.ps1'
            $detection = Get-Result -Results $script:Results -Policy 'Widget: 2.0' -Role 'detection'
            $detection.State | Should-Be 'InSync'
            $detection.Kind | Should-Be 'Win32App'
        }

        It 'reports a policy with no local file as Missing and a local file with no script as NotInTenant' {
            $missing = Get-Result -Results $script:Results -Policy 'Report-Only' -Role 'detection'
            $missing.State | Should-Be 'Missing'
            $missing.TenantHash.Length | Should-Be 12
            $missing.Detail | Should-BeLikeString "no local file for the detection script of 'Report-Only'*"
            $orphan = Get-Result -Results $script:Results -Policy 'Report-Only' -Role 'remediation'
            $orphan.State | Should-Be 'NotInTenant'
            $orphan.LocalPath | Should-BeLikeString '*Report-Only\Remediate.ps1'
        }

        It 'compares content case-sensitively' {
            $root = Join-Path $TestDrive 'case'
            $file = Join-Path $root 'Remediations\Fix-Widget\Detect.ps1'
            $null = New-Item -ItemType Directory -Path (Split-Path $file -Parent) -Force
            $upper = $script:Detect -replace 'exit 0', 'EXIT 0'
            [System.IO.File]::WriteAllBytes($file, (Get-ByteArray -Text $upper -Bom))
            $results = @(Compare-IntuneDeployedScript -Path $root -Kind Remediation -Name 'Fix-Widget')
            $detection = Get-Result -Results $results -Policy 'Fix-Widget' -Role 'detection'
            $detection.State | Should-Be 'Drifted'
            @($detection.Differences) | Should-BeCollection @('Content')
            $detection.Detail | Should-BeLikeString 'content differs from line 2*'
        }

        It 'reports two local candidates as Ambiguous' {
            $dup = $script:Results | Where-Object PolicyName -eq 'Dup'
            $dup.State | Should-Be 'Ambiguous'
            $dup.Detail | Should-BeLikeString '2 local candidates: *Dup.ps1, *Dup\run.ps1'
        }

        It 'compares an explicit directive with the policy settings and leaves inferred values alone' {
            @($script:Results | Where-Object PolicyName -eq 'Ctx-Check').Count | Should-Be 1
            $context = Get-Result -Results $script:Results -Policy 'Ctx-Check' -Role 'detection'
            $context.State | Should-Be 'Drifted'
            @($context.Differences) | Should-BeCollection @('Settings')
            $context.Detail | Should-Be 'Context=User locally, the policy runs as System'
            # Set-Wallpaper runs as user, 32-bit, and its local file says nothing: no Settings difference
            $wallpaper = $script:Results | Where-Object PolicyName -eq 'Set-Wallpaper'
            @($wallpaper.Differences) | Should-NotContainCollection 'Settings'
        }

        It 'produces nothing for an app whose rules carry no script' {
            @($script:Results | Where-Object PolicyName -eq 'Widget 1.0').Count | Should-Be 0
        }
    }

    Context 'Selection and -Map' {
        It 'limits the comparison by kind and name' {
            $results = @(Compare-IntuneDeployedScript -Path $script:Root -Kind Remediation -Name 'Fix-*')
            $results.PolicyName | Should-All { $_ -eq 'Fix-Widget' }
            $results.Count | Should-Be 2
            Should-Invoke Invoke-IslGraphRequest -ModuleName IntuneScriptLab -ParameterFilter {
                $Uri -like '*mobileApps*'
            } -Times 0 -Exactly
        }
        It 'selects by id alone when no name is given' {
            $results = @(Compare-IntuneDeployedScript -Path $script:Root -Id 'rem-c')
            $results.PolicyName | Should-All { $_ -eq 'Ctx-Check' }
            $results.Count | Should-Be 1
        }

        It 'uses -Settings for the settings comparison instead of the nearest settings file' {
            # Set-Wallpaper's local file says nothing, so the settings hashtable is what gets compared
            $compareSplat = @{ Path = $script:Root; Name = 'Set-Wallpaper'; Settings = @{ Context = 'System' } }
            $wallpaper = @(Compare-IntuneDeployedScript @compareSplat)
            $wallpaper.Count | Should-Be 1
            @($wallpaper[0].Differences) | Should-ContainCollection 'Settings'
            $wallpaper[0].Detail | Should-BeLikeString '*Context=System locally, the policy runs as User*'
        }

        It 'takes local files from -Map by role, relative to -Path, and reports an entry with no policy' {
            $map = @{
                'Fix-Widget' = @{ Detection = 'Remediations\Fix-Widget\Detect.ps1'; Remediation = 'nowhere.ps1' }
                'Dup'        = 'Scripts\Dup.ps1'
                'Gone'       = 'Scripts\gone.ps1'
            }
            $compareSplat = @{ Path = $script:Root; Map = $map; Kind = 'Remediation', 'PlatformScript' }
            $results = @(Compare-IntuneDeployedScript @compareSplat)
            (Get-Result -Results $results -Policy 'Fix-Widget' -Role 'detection').State | Should-Be 'InSync'
            $remediation = Get-Result -Results $results -Policy 'Fix-Widget' -Role 'remediation'
            $remediation.State | Should-Be 'Missing'
            $remediation.Detail | Should-BeLikeString '*nowhere.ps1 does not exist'
            ($results | Where-Object PolicyName -eq 'Dup').State | Should-Be 'InSync'
            $gone = $results | Where-Object PolicyName -eq 'Gone'
            $gone.State | Should-Be 'NotInTenant'
            $gone.Role | Should-Be 'policy'
            @($gone.Differences).Count | Should-Be 0
            $gone.LocalPath | Should-Be 'Scripts\gone.ps1'
            $gone.Detail | Should-BeLikeString "no policy named 'Gone'*Remediation, PlatformScript*"
        }
    }

    Context 'Error Handling' {
        It 'refuses a -Path that is not a folder' {
            $file = Join-Path $script:Root 'Scripts\Dup.ps1'
            { Compare-IntuneDeployedScript -Path $file } | Should-Throw -ExceptionMessage '*must be a folder*'
        }

        It 'refuses a -Path that does not exist' {
            { Compare-IntuneDeployedScript -Path (Join-Path $TestDrive 'nope') } | Should-Throw
        }
    }
}
