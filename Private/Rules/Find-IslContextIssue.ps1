function Find-IslContextIssue {
    <#
    .SYNOPSIS
        Flags per-user locations in SYSTEM scripts and privileged writes in user scripts.

    .DESCRIPTION
        As SYSTEM, HKCU: is the SYSTEM account's own hive, USERPROFILE is
        C:\WINDOWS\system32\config\systemprofile, APPDATA sits under it, TEMP is C:\WINDOWS\TEMP,
        there is no console session and no mapped drives. A script written and tested in the
        admin's own session works there and silently does the wrong thing under Intune.
        Running as the signed-in user has the opposite problem: standard users can't write HKLM
        or Program Files.

    .PARAMETER Context
        The IntuneScriptLab.ScriptContext from Get-IslScriptContext: AST, tokens, bytes and the
        effective ScriptType, Context and Architecture.

    .EXAMPLE
        Find-IslContextIssue -Context (Get-IslScriptContext -Path .\Detect.ps1)

        The findings this rule produces for one script, as IntuneScriptLab.Finding objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $rule = 'IslContextIssue'
    $ast = $Context.Ast
    $literals = @(Get-IslStringLiteral -Ast $ast)
    $variables = @(Find-IslAstNode -Ast $ast -TypeName VariableExpressionAst)

    if ($Context.Context -eq 'System') {
        $evidence = ('SYSTEM context: User=NT AUTHORITY\SYSTEM, session 0, ' +
            ('USERPROFILE=C:\WINDOWS\system32\config\systemprofile, APPDATA under it, TEMP=C:\WINDOWS\TEMP ' +
                '(REM-PROBE-SYS64, PS-PROBE-SYS64)'))

        $hkcuPattern = '(?i)^(HKCU:|Registry::HKEY_CURRENT_USER|HKEY_CURRENT_USER\\)'
        foreach ($literal in ($literals | Where-Object { $_.Value -match $hkcuPattern })) {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Error'
                Context  = $Context
                Extent   = $literal.Extent
                Message  = ('HKCU: under SYSTEM is the SYSTEM account''s hive, not the signed-in ' +
                    'user''s. Load the user''s hive via HKU\<SID> or run the script in user context')
                Evidence = $evidence
            }
            New-IslFinding @findingSplat
        }
        foreach ($variable in ($variables | Where-Object {
                    $_.VariablePath.UserPath -match ('(?i)^env:(USERPROFILE|APPDATA|' +
            'LOCALAPPDATA|USERNAME|HOMEPATH|' +
            'HOMEDRIVE|OneDrive|' +
            'OneDriveCommercial)$|^HOME$') })) {
            $name = $variable.VariablePath.UserPath
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Error'
                Context  = $Context
                Extent   = $variable.Extent
                Message  = ("`$$name resolves to the SYSTEM profile (systemprofile), not the signed-in user. " +
                    "Look the user up (e.g. via explorer.exe's owner or HKU) or run in user context")
                Evidence = $evidence
            }
            New-IslFinding @findingSplat
        }
        foreach ($variable in ($variables |
            Where-Object { $_.VariablePath.UserPath -match '(?i)^env:(TEMP|TMP)$' })) {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Information'
                Context  = $Context
                Extent   = $variable.Extent
                Message  = ("`$$($variable.VariablePath.UserPath) is C:\WINDOWS\TEMP under SYSTEM, which is " +
                    'fine if that is what you expect')
                Evidence = $evidence
            }
            New-IslFinding @findingSplat
        }
        $userFolders = Find-IslAstNode -Ast $ast -TypeName InvokeMemberExpressionAst -Where {
            param($node) $node.Extent.Text -match ('(?i)GetFolderPath\(\s*[''"]?(ApplicationData|' +
                ('LocalApplicationData|UserProfile|MyDocuments|Personal|Desktop|DesktopDirectory|Favorites|' +
                    'StartMenu|Startup|MyPictures|MyMusic|MyVideos)'))
        }
        foreach ($node in $userFolders) {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Error'
                Context  = $Context
                Extent   = $node.Extent
                Message  = ('GetFolderPath for a per-user folder returns the SYSTEM profile''s folder ' +
                    'under SYSTEM')
                Evidence = $evidence
            }
            New-IslFinding @findingSplat
        }
        foreach ($literal in ($literals | Where-Object { $_.Value -match '^[D-Zd-z]:\\' })) {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Warning'
                Context  = $Context
                Extent   = $literal.Extent
                Message  = ("Drive $($literal.Value.Substring(0, 2)) is not mapped for SYSTEM; mapped drives " +
                    'belong to the user session. Use a UNC path and make sure the computer account ' +
                    'can reach it')
                Evidence = $evidence
            }
            New-IslFinding @findingSplat
        }
    }

    if ($Context.Context -eq 'User') {
        $evidence = ('User context ran as AzureAD\<user> in the console session with that user''s profile and ' +
            'rights (REM-PROBE-USER64, PS-PROBE-USER)')
        $writers = 'Set-ItemProperty', 'New-ItemProperty', 'New-Item', 'Remove-Item', 'Remove-ItemProperty',
            'Rename-Item', 'Copy-Item', 'Move-Item', 'Set-Content', 'Add-Content', 'Out-File'
        foreach ($command in (Find-IslCommand -Ast $ast -Name $writers)) {
            if ($command.Extent.Text -match ('(?i)HKLM:|HKEY_LOCAL_MACHINE|\\Program ' +
                'Files|\\Windows\\|\$env:(ProgramFiles|windir|SystemRoot|ProgramData)')) {
                $findingSplat = @{
                    RuleName = $rule
                    Severity = 'Warning'
                    Context  = $Context
                    Extent   = $command.Extent
                    Message  = ("$($command.GetCommandName()) to a machine-wide location runs as the " +
                        'signed-in user, who is usually not an administrator; it will fail with access denied')
                    Evidence = $evidence
                }
                New-IslFinding @findingSplat
            }
        }
        $privileged = 'Start-Service', 'Stop-Service', 'Restart-Service', 'Set-Service', 'New-Service',
            'Install-WindowsFeature', 'Enable-WindowsOptionalFeature', 'Add-AppxProvisionedPackage',
            'Set-MpPreference', 'Add-MpPreference'
        foreach ($command in (Find-IslCommand -Ast $ast -Name $privileged)) {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Warning'
                Context  = $Context
                Extent   = $command.Extent
                Message  = ("$($command.GetCommandName()) needs administrator rights; in user context the " +
                    'script runs as the signed-in user')
                Evidence = $evidence
            }
            New-IslFinding @findingSplat
        }
        # Not something the script can fix, but the reason a user-context script never runs on part
        # of a fleet; Win32 requirement scripts are the one kind that does run there
        if ($Context.ScriptType -in 'Detection', 'Remediation', 'PlatformScript') {
            $findingSplat = @{
                RuleName = $rule
                Severity = 'Information'
                Context  = $Context
                Message  = ('User context runs only on Entra joined or hybrid-joined devices: on an ' +
                    'Entra-registered device the agent downloads the policy and skips it. Deploy as SYSTEM ' +
                    'if registered devices must be covered')
                Evidence = ('IntuneManagementExtension.log on a registered device: "This is not ' +
                    'AADJ/HAADJ device, skip user context"; the same scripts ran as AzureAD\<user> on a ' +
                    'joined device (join-type experiments, REM-PROBE-USER64, PS-PROBE-USER)')
            }
            New-IslFinding @findingSplat
        }
    }
}
