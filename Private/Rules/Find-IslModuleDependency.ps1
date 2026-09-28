function Find-IslModuleDependency {
    <#
    .SYNOPSIS
        Flags modules a script needs that the agent's SYSTEM session will not have.

    .DESCRIPTION
        Under the agent a script runs as SYSTEM in Windows PowerShell 5.1 with a module path of the
        systemprofile's Documents folder, Program Files\WindowsPowerShell\Modules and the System32
        modules (REM-PSMODULEPATH). A module installed for a user, or one that comes with RSAT, Azure
        or the Graph SDK, is not there unless it was installed machine-wide. Import-Module,
        #Requires -Modules and using module that name a module outside the in-box list
        (Get-IslInboxModule) are reported, as is installing one from the gallery inside the script,
        which depends on the NuGet provider and gallery reach in that session (REM-INSTALL-MODULE).

    .PARAMETER Context
        The IntuneScriptLab.ScriptContext from Get-IslScriptContext: AST, tokens, bytes and the
        effective ScriptType, Context and Architecture.

    .EXAMPLE
        Find-IslModuleDependency -Context (Get-IslScriptContext -Path .\Detect.ps1)

        The findings this rule produces for one script, as IntuneScriptLab.Finding objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $rule = 'IslModuleDependency'
    $inbox = Get-IslInboxModule
    $pathEvidence = ('SYSTEM''s PSModulePath under the agent is the systemprofile Documents folder, Program ' +
        'Files\WindowsPowerShell\Modules and System32\WindowsPowerShell\v1.0\Modules; 90 modules were available ' +
        'on a plain Windows 11 device, none of them user-installed (REM-PSMODULEPATH)')
    $installEvidence = ('Find-Module and Install-Module in a SYSTEM detection script never returned: no NuGet ' +
        'provider on the device, the process stuck on the provider prompt with 12 s of CPU in 20 minutes, ' +
        'killed at the 60-minute timeout (detectionState scriptError) while every remediation queued behind ' +
        'it waited (REM-INSTALL-MODULE)')

    function Test-InBox {
        param([string]$Name)
        # A path is a file the script ships or references, not a module by name; leave it to the
        # relative-path rule
        if ($Name -match '[\\/]' -or $Name -match '\.psm?1$|\.psd1$') { return $true }
        if ($Name -match '[\*\?\$]') { return $true }
        $Name -in $inbox
    }

    function Write-Missing {
        param([string]$Name, $Extent, [string]$How)
        $findingSplat = @{
            RuleName = $rule
            Severity = 'Warning'
            Context  = $Context
            Extent   = $Extent
            Message  = ("$How names $Name, which is not in-box under the agent's SYSTEM session. It must be " +
                'installed machine-wide (Program Files\WindowsPowerShell\Modules) before the script runs; a ' +
                '#Requires for a missing module stops the script before it starts (exit 1, ' +
                'ScriptRequiresMissingModules) and a detection failing that way still runs the remediation')
            Evidence = $pathEvidence + '; a #Requires -Modules for a module the device lacks exited 1 without ' +
                'running, the remediation ran anyway, and Graph reported detectionState fail, remediationState ' +
                'remediationFailed (REM-REQUIRES-MODULE)'
        }
        New-IslFinding @findingSplat
    }

    foreach ($required in @($Context.Ast.ScriptRequirements.RequiredModules | Where-Object { $_ })) {
        if (-not (Test-InBox -Name "$($required.Name)")) {
            Write-Missing -Name $required.Name -Extent $Context.Ast.Extent -How '#Requires -Modules'
        }
    }
    foreach ($using in (Find-IslAstNode -Ast $Context.Ast -TypeName UsingStatementAst -Where {
                param($node) "$($node.UsingStatementKind)" -eq 'Module'
            })) {
        $name = if ($using.Name) { $using.Name.Value } else { "$($using.ModuleSpecification.Extent.Text)" }
        if (-not (Test-InBox -Name $name)) { Write-Missing -Name $name -Extent $using.Extent -How 'using module' }
    }
    foreach ($command in (Find-IslCommand -Ast $Context.Ast -Name 'Import-Module', 'ipmo')) {
        $elements = $command.CommandElements
        $names = for ($i = 1; $i -lt $elements.Count; $i++) {
            $element = $elements[$i]
            if ($element.GetType().Name -eq 'CommandParameterAst') {
                $isName = 'Name'.StartsWith($element.ParameterName, 'OrdinalIgnoreCase')
                if ($isName -and $i + 1 -lt $elements.Count) {
                    $i++
                    $elements[$i]
                }
                continue
            }
            if ($i -eq 1) { $element }
        }
        foreach ($nameElement in @($names)) {
            $literals = if ($nameElement.GetType().Name -eq 'ArrayLiteralAst') { $nameElement.Elements }
            else { @($nameElement) }
            foreach ($literal in $literals) {
                if ($literal.GetType().Name -ne 'StringConstantExpressionAst') { continue }
                if (-not (Test-InBox -Name $literal.Value)) {
                    Write-Missing -Name $literal.Value -Extent $command.Extent -How 'Import-Module'
                }
            }
        }
    }

    $installers = 'Install-Module', 'Install-PSResource', 'Install-Package', 'Save-Module', 'Update-Module'
    foreach ($command in (Find-IslCommand -Ast $Context.Ast -Name $installers)) {
        $findingSplat = @{
            RuleName = $rule
            Severity = 'Warning'
            Context  = $Context
            Extent   = $command.Extent
            Message  = ("$($command.GetCommandName()) inside the script installs from the gallery as SYSTEM on " +
                'every device that runs it. Without the NuGet provider it waits on a prompt nobody can answer ' +
                'until the 60-minute timeout, and every other remediation on the device waits behind it. Ship ' +
                'the module with the content or install it once with a separate policy')
            Evidence = $installEvidence
        }
        New-IslFinding @findingSplat
    }
}
