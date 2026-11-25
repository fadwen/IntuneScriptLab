#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The module's shape, checked separately from its behaviour: the manifest and the psm1 agree
    on what is exported, every rule in Private\Rules is registered in the run order, and the
    public function documents itself.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ManifestPath = Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1'
    # The one file that imports the module anew: it asserts what a newly imported module looks
    # like. It leaves the module loaded for the files after it, as they do
    Import-Module $script:ManifestPath -Force
}

Describe 'IntuneScriptLab module contract' -Tag 'Unit', 'Contract' {

    It 'has a valid manifest' {
        Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop | Should-NotBeNull
    }

    It 'declares no required modules, so it runs in a bare CI container' {
        @((Test-ModuleManifest -Path $script:ManifestPath).RequiredModules).Count | Should-Be 0
    }

    It 'keeps the Gallery metadata within the limits the Gallery enforces: <Field>' -ForEach @(
        @{ Field = 'ReleaseNotes'; Limit = 10600 }
        @{ Field = 'Description'; Limit = 4000 }
    ) {
        # The Gallery refused 0.27.0's first upload: "A package's ReleaseNotes property extracted from
        # the PowerShell manifest may not be more than 10600 characters long". Description carries
        # NuGet's 4,000. A line break is counted as two characters, the larger of the two possible
        # counts, because the publish writes the notes with the line endings of the system that
        # publishes. Build/Publish-Module.ps1 makes the same two measurements; this fails the pull
        # request instead of the tag-driven release. The tags are not measured: the list the Gallery
        # shows, with a tag for every exported function, has no 4,000-character limit.
        $manifest = Test-ModuleManifest -Path $script:ManifestPath
        $text = if ($Field -eq 'ReleaseNotes') { "$($manifest.ReleaseNotes)" } else { "$($manifest.Description)" }
        $text.Replace("`r`n", "`n").Replace("`n", "`r`n").Length | Should-BeLessThanOrEqual $Limit
    }

    It 'has a format view for every output type an exported command declares' {
        # A result type without a view prints as a property dump; the view is part of the command's contract
        $declared = @(Get-Command -Module IntuneScriptLab -CommandType Function | ForEach-Object {
                $_.OutputType.Name
            } | Where-Object { $_ -like 'IntuneScriptLab.*' } | Sort-Object -Unique)
        $declared.Count | Should-BeGreaterThan 10
        [xml]$format = Get-Content (Join-Path $script:ModuleRoot 'IntuneScriptLab.Format.ps1xml') -Raw
        $viewed = @($format.Configuration.ViewDefinitions.View.ViewSelectedBy.TypeName | Sort-Object -Unique)
        @($declared | Where-Object { $_ -notin $viewed }) | Should-BeCollection @()
    }

    It 'exports exactly the public functions' {
        $exported = @((Get-Command -Module IntuneScriptLab -CommandType Function).Name | Sort-Object)
        $exported | Should-BeCollection @(
            'Assert-BeIntuneApplicable'
            'Assert-BeIntuneDetected'
            'Assert-HaveIntuneRunState'
            'Assert-HaveIntuneStatus'
            'Assert-NotBeIntuneApplicable'
            'Assert-NotBeIntuneDetected'
            'Assert-PassIntuneAnalysis'
            'Compare-IntuneDeployedScript'
            'Export-IntuneAgentDiagnostic'
            'Export-IntuneFindingSarif'
            'Get-IntuneAgentLog'
            'Get-IntuneAgentTimeline'
            'Get-IntuneAnalyzerRulePath'
            'Get-IntuneScriptHealth'
            'Invoke-IntuneDetectionTest'
            'Invoke-IntunePlatformScriptTest'
            'Invoke-IntuneRemediationTest'
            'Invoke-IntuneRequirementTest'
            'Invoke-IntuneWin32AppTest'
            'Repair-IntuneScript'
            'Test-IntuneAssignmentFilter'
            'Test-IntuneDeployedScript'
            'Test-IntuneScript'
            'Test-IntuneWin32Requirement'
            'Test-IntuneWin32Rule'
        )
    }

    It 'exports the Should- aliases the manifest declares, and imports without a verb warning' {
        $manifest = Test-ModuleManifest -Path $script:ManifestPath
        $aliases = @((Get-Command -Module IntuneScriptLab -CommandType Alias).Name | Sort-Object)
        $aliases | Should-BeCollection @($manifest.ExportedAliases.Keys | Sort-Object)
        $warnings = @()
        Import-Module $script:ManifestPath -Force -WarningVariable warnings 3>$null
        @($warnings).Count | Should-Be 0
    }

    It 'registers every rule file in the run order, and nothing else' {
        $ruleFiles = @(Get-ChildItem (Join-Path $script:ModuleRoot 'Private\Rules\*.ps1') |
                ForEach-Object BaseName | Sort-Object)
        $registered = @(InModuleScope IntuneScriptLab { $script:RuleOrder } | Sort-Object)
        $registered | Should-BeCollection $ruleFiles
    }

    It 'gives every public function help with worked examples (read from the shipped MAML)' {
        # Counted first, so that an empty list cannot pass the loop without checking anything
        $exported = @((Import-PowerShellDataFile -LiteralPath $script:ManifestPath).FunctionsToExport)
        $commands = @(Get-Command -Module IntuneScriptLab -CommandType Function)
        $commands | Should-BeCollection -Count $exported.Count
        foreach ($command in $commands) {
            $help = Get-Help $command.Name -Full
            $help.Synopsis | Should-NotBeWhiteSpaceString
            @($help.Examples.Example).Count | Should-BeGreaterThanOrEqual 3
        }
    }

    It 'gives every public function a one-line synopsis of at most 80 characters, the same in both places' {
        $exported = @((Import-PowerShellDataFile -LiteralPath $script:ManifestPath).FunctionsToExport)
        $commands = @(Get-Command -Module IntuneScriptLab -CommandType Function)
        $commands | Should-BeCollection -Count $exported.Count
        foreach ($command in $commands) {
            $synopsis = (Get-Help $command.Name).Synopsis.Trim()
            $synopsis.Contains("`n") | Should-BeFalse -Because "the synopsis of $($command.Name) is one line"
            $synopsis.Length | Should-BeLessThanOrEqual 80 -Because "DOC-10 limits $($command.Name)"
            # The one-line .SYNOPSIS beside .EXTERNALHELP is what a reader of the source sees
            $source = $command.ScriptBlock.Ast.GetHelpContent().Synopsis.Trim()
            $source | Should-Be $synopsis -Because "the source and the help of $($command.Name) say the same"
        }
    }

    It 'ships the about_IntuneScriptLab topic and Get-Help finds it' {
        $topic = Join-Path $script:ModuleRoot 'en-US\about_IntuneScriptLab.help.txt'
        Test-Path $topic | Should-BeTrue
        $text = Get-Content $topic -Raw
        $text | Should-BeLikeString 'TOPIC*about_IntuneScriptLab*SHORT DESCRIPTION*LONG DESCRIPTION*SEE ALSO*'
        # Every exported command is mentioned, so the topic cannot drift behind the module
        foreach ($command in (Get-Command -Module IntuneScriptLab -CommandType Function).Name) {
            if ($command -like 'Assert-*') { continue }
            $text | Should-BeLikeString "*$command*" -Because "the about topic should name $command"
        }
        $help = @(Get-Help about_IntuneScriptLab -ErrorAction SilentlyContinue)
        "$help" | Should-BeLikeString '*IntuneScriptLab*evidence*'
    }

    It 'points every public function at the external help the module ships' {
        # Without .EXTERNALHELP the comment block wins and en-US\IntuneScriptLab-Help.xml is dead
        # weight; the keyword must sit inside the <# #> block with the file name and no path.
        Test-Path (Join-Path $script:ModuleRoot 'en-US\IntuneScriptLab-Help.xml') | Should-BeTrue
        $exported = @((Get-Command -Module IntuneScriptLab -CommandType Function).Name)
        foreach ($file in Get-ChildItem (Join-Path $script:ModuleRoot 'Public\*.ps1')) {
            $source = Get-Content $file.FullName -Raw
            # Helpers a Public file defines for itself stay on comment-based help
            $functions = @([regex]::Matches($source, '(?m)^function ([\w-]+)') |
                    Where-Object { $_.Groups[1].Value -in $exported }).Count
            $keywords = ([regex]::Matches($source,
                    '(?m)^    <#\r?\n    \.EXTERNALHELP IntuneScriptLab-Help\.xml\r?$')).Count
            $keywords | Should-Be $functions -Because "$($file.Name) exports $functions function(s)"
        }
    }

    It 'has PlatyPS Markdown for every exported command, with no placeholders left' {
        $docs = Join-Path $script:ModuleRoot 'docs\IntuneScriptLab'
        $documented = @((Get-ChildItem $docs -Filter *.md).BaseName | Where-Object { $_ -ne 'IntuneScriptLab' } |
                Sort-Object)
        $documented | Should-BeCollection @((Get-Command -Module IntuneScriptLab -CommandType Function).Name |
                Sort-Object)
        # A new command leaves "{{ Fill in ... }}", a new parameter "{{ Fill <Name> Description }}"
        @(Select-String -Path "$docs\*.md" -Pattern '\{\{\s*Fill' -List).Count | Should-Be 0
    }

    It 'ships a PSScriptAnalyzer Measure- function for every rule in the run order, and nothing else' {
        # PSScriptAnalyzer discovers rules by parsing the file, so the functions are written out and
        # can drift from the rule list; this is what keeps them in step
        $rulesModule = Join-Path $script:ModuleRoot 'PSScriptAnalyzer\IntuneScriptLab.Rules.psm1'
        $source = Get-Content $rulesModule -Raw
        $defined = @([regex]::Matches($source, '(?m)^function (Measure-[\w]+)') |
                ForEach-Object { $_.Groups[1].Value } | Sort-Object)
        $expected = @(InModuleScope IntuneScriptLab { $script:RuleOrder } |
                ForEach-Object { $_ -replace '^Find-', 'Measure-' }) + 'Measure-IslAssumedContext'
        $defined | Should-BeCollection @($expected | Sort-Object)
        $exported = @([regex]::Matches($source, "(?m)^\s+'(Measure-[\w]+)'") |
                ForEach-Object { $_.Groups[1].Value } | Sort-Object)
        $exported | Should-BeCollection $defined
    }

    It 'keeps the rules private' {
        $commandSplat = @{
            Module = 'IntuneScriptLab'
            Name = 'Find-IslExitCodeIssue'
            ErrorAction = 'SilentlyContinue'
        }
        Get-Command @commandSplat | Should-BeNull
    }

    It 'runs its functions under strict mode' {
        # Set once at the top of the root module: a read of a variable that was never assigned is
        # an error in every function, where it used to be a silent $null
        { InModuleScope IntuneScriptLab { $null = $neverAssignedAnywhere } } |
            Should-Throw -ExceptionMessage '*neverAssignedAnywhere*'
    }

    Context 'When a part of the module cannot be loaded' {
        BeforeAll {
            # Each copy is imported in a new process: a second module of this name imported here
            # would stand beside the one under test for the rest of the run
            $script:Shell = (Get-Process -Id $PID).Path
            function script:Import-ModuleCopy {
                <#
                .SYNOPSIS
                    Copies the module under TestDrive, changes it and imports it in a new process.

                .DESCRIPTION
                    The import is a plain one, as a user types it. Returns the exit code of that process
                    and what it wrote: 'imported' when the module is loaded afterwards, and otherwise
                    the message of the error that ended the import, followed by 'not imported'.

                .PARAMETER Name
                    The folder under TestDrive that holds this copy.

                .PARAMETER Change
                    Changes the copy before it is imported. It receives the folder of the copy.

                .EXAMPLE
                    Import-ModuleCopy -Name 'Intact' -Change { }

                    Imports an unchanged copy.

                .INPUTS
                    None.

                .OUTPUTS
                    System.Management.Automation.PSCustomObject. ExitCode and Output of the process.
                #>
                [CmdletBinding()]
                [OutputType([System.Management.Automation.PSCustomObject])]
                param(
                    [Parameter(Mandatory)]
                    [string]$Name,

                    [Parameter(Mandatory)]
                    [scriptblock]$Change
                )
                $copy = Join-Path (Join-Path $TestDrive $Name) 'IntuneScriptLab'
                $null = New-Item -ItemType Directory -Path $copy -Force
                $parts = @(
                    'IntuneScriptLab.psd1'
                    'IntuneScriptLab.psm1'
                    'IntuneScriptLab.Format.ps1xml'
                    'Data'
                    'Private'
                    'Public'
                )
                foreach ($part in $parts) {
                    Copy-Item -LiteralPath (Join-Path $script:ModuleRoot $part) -Destination $copy -Recurse
                }
                & $Change $copy
                # The child reports the failure on its output: a native error stream read under an
                # error preference of Stop, which a CI step sets, would end the test instead
                $manifest = Join-Path $copy 'IntuneScriptLab.psd1'
                $import = "try { Import-Module '$manifest' } catch { 'error: ' + `$_.Exception.Message }"
                $report = "if (Get-Module -Name IntuneScriptLab) { 'imported' } else { 'not imported'; exit 1 }"
                $command = "$import; $report"
                $arguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', $command)
                $output = & $script:Shell @arguments
                [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = "$output" }
            }
        }

        It 'imports an intact copy, so that the failures below come from what was broken' {
            $result = Import-ModuleCopy -Name 'Intact' -Change { }
            $result.Output | Should-Be 'imported'
            $result.ExitCode | Should-Be 0
        }

        It 'fails the import when a function file <Problem>' -ForEach @(
            @{ Problem = 'throws while it loads'; Body = "throw 'this file cannot load'" }
            @{ Problem = 'does not parse'; Body = 'function Get-IslBrokenFile {' }
        ) {
            # The file that does not parse is the case the loader's rethrow exists for: dot-sourcing
            # it is an error that ends only that statement, and the import used to carry on and
            # leave the module loaded without the commands of that file
            $result = Import-ModuleCopy -Name ($Problem -replace '\W', '-') -Change {
                param($copy)
                $broken = Join-Path $copy 'Private\Get-IslBrokenFile.ps1'
                Set-Content -LiteralPath $broken -Value $Body -Encoding ascii
            }
            $result.ExitCode | Should-Be 1
            $result.Output | Should-BeLikeString 'error: *not imported'
        }

        It 'fails the import when the <Folder> folder is missing' -ForEach @(
            @{ Folder = 'Private\Rules' }
            @{ Folder = 'Public' }
        ) {
            $result = Import-ModuleCopy -Name ($Folder -replace '\W', '-') -Change {
                param($copy)
                Remove-Item -LiteralPath (Join-Path $copy $Folder) -Recurse -Force
            }
            $result.ExitCode | Should-Be 1
            $result.Output | Should-BeLikeString "error: *$($Folder -replace '^.*\\')*is missing*not imported"
        }

        It 'fails the import when a data file <Problem>' -ForEach @(
            @{ Problem = 'is missing'; Body = $null }
            @{ Problem = 'does not parse'; Body = '@{ Modules = @(' }
        ) {
            # The tables the commands read are data (MOD-20); a module without them would import
            # and then fail in every command that reads one
            $result = Import-ModuleCopy -Name ('data-' + ($Problem -replace '\W', '-')) -Change {
                param($copy)
                $dataFile = Join-Path $copy 'Data\InboxModules.psd1'
                if ($null -eq $Body) {
                    Remove-Item -LiteralPath $dataFile
                } else {
                    Set-Content -LiteralPath $dataFile -Value $Body -Encoding ascii
                }
            }
            $result.ExitCode | Should-Be 1
            $result.Output | Should-BeLikeString 'error: *not imported'
        }
    }

    It 'loads on Windows PowerShell 5.1 as well as PowerShell 7' {
        # The rules reference PowerShell 7 AST types by name only; a hard type reference would
        # break import on 5.1, which is where many admins will run this.
        $manifest = Test-ModuleManifest -Path $script:ManifestPath
        $manifest.PowerShellVersion | Should-Be ([version]'5.1')
        if (Get-Command powershell.exe -ErrorAction SilentlyContinue) {
            # Bypass: the module's own loadability is under test, not the machine's execution policy
            $arguments = @(
                '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command'
                "Import-Module '$($script:ManifestPath)' -ErrorAction Stop; (Get-Command Test-IntuneScript).Name"
            )
            $result = & powershell.exe @arguments
            $result | Should-Be 'Test-IntuneScript'
        }
    }
}
