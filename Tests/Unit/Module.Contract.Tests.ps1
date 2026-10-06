#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The module's shape, checked separately from its behaviour: the manifest and the psm1 agree
    on what is exported, every rule in Private\Rules is registered in the run order, and the
    public function documents itself.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ManifestPath = Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1'
    Import-Module $script:ManifestPath -Force
}

AfterAll {
    Remove-Module IntuneScriptLab -Force -ErrorAction SilentlyContinue
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
        @{ Field = 'Tags'; Limit = 4000 }
    ) {
        # The Gallery refused 0.27.0's first upload: "A package's ReleaseNotes property extracted from
        # the PowerShell manifest may not be more than 10600 characters long". Description and Tags
        # carry NuGet's 4,000. The tags it measures include the ones the publish adds, PSModule, a
        # PSEdition_ tag per edition, PSFunction_ and PSCommand_ per exported function and
        # PSIncludes_Function: the list the Gallery shows for 0.27.0. Build/Publish-Module.ps1 checks
        # the same three; this fails the pull request instead of the tag-driven release.
        $manifest = Test-ModuleManifest -Path $script:ManifestPath
        $text = switch ($Field) {
            'ReleaseNotes' { "$($manifest.ReleaseNotes)" }
            'Description' { "$($manifest.Description)" }
            'Tags' {
                $tags = @($manifest.Tags) + 'PSModule'
                $tags += @($manifest.CompatiblePSEditions | ForEach-Object { "PSEdition_$_" })
                foreach ($name in @($manifest.ExportedFunctions.Keys | Sort-Object)) {
                    $tags += "PSFunction_$name", "PSCommand_$name"
                }
                ($tags + 'PSIncludes_Function') -join ' '
            }
        }
        $text.Length | Should-BeLessThanOrEqual $Limit
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
        foreach ($command in (Get-Command -Module IntuneScriptLab -CommandType Function)) {
            $help = Get-Help $command.Name -Full
            $help.Synopsis | Should-NotBeWhiteSpaceString
            @($help.Examples.Example).Count | Should-BeGreaterThanOrEqual 3
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
            Module      = 'IntuneScriptLab'
            Name        = 'Find-IslExitCodeIssue'
            ErrorAction = 'SilentlyContinue'
        }
        Get-Command @commandSplat | Should-BeNull
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
