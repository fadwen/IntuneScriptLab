#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The README's list of the edits Repair-IntuneScript can make, held against the rules: every rule
    whose findings carry a Fix is in the list, and the list names no rule that has none. The list
    had drifted once (#152): it left out the -ErrorAction Stop edit and counted its edits wrong. A
    rule offers an edit where its file assigns a Fix, either in the finding's hashtable or on the
    splat that builds it.
#>

BeforeDiscovery {
    $rulesFolder = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Private\Rules'
    $script:RulesWithFix = @(
        foreach ($file in Get-ChildItem -LiteralPath $rulesFolder -Filter 'Find-Isl*.ps1') {
            if (Select-String -LiteralPath $file.FullName -Pattern '\bFix\s*=' -Quiet) {
                @{ Rule = $file.BaseName -replace '^Find-', '' }
            }
        }
    )
}

BeforeAll {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $readme = [System.IO.File]::ReadAllText((Join-Path $repositoryRoot 'README.md')).Replace("`r`n", "`n")
    $start = $readme.IndexOf('Some findings come with an edit the tool can make for you')
    $end = $readme.IndexOf('`Repair-IntuneScript` applies them', $start)
    $script:EditList = ''
    if ($start -ge 0 -and $end -gt $start) {
        $script:EditList = $readme.Substring($start, $end - $start)
    }
    # The same list as in BeforeDiscovery, for the test that reads it: discovery's variables are not
    # there when the tests run
    $rulesFolder = Join-Path $repositoryRoot 'Private\Rules'
    $script:OfferingRules = @(
        foreach ($file in Get-ChildItem -LiteralPath $rulesFolder -Filter 'Find-Isl*.ps1') {
            if (Select-String -LiteralPath $file.FullName -Pattern '\bFix\s*=' -Quiet) {
                $file.BaseName -replace '^Find-', ''
            }
        }
    )
}

Describe 'The README''s list of the edits Repair-IntuneScript makes' -Tag 'Unit', 'Documentation' {

    It 'is in the README, between its opening sentence and the paragraph after it' {
        $script:EditList.Length | Should-BeGreaterThan 0
    }

    It 'lists <Rule>, which offers an edit' -ForEach $script:RulesWithFix {
        $script:EditList.Contains("- ``$Rule``:") | Should-BeTrue -Because "$Rule assigns a Fix"
    }

    It 'names no rule that offers no edit' {
        $named = @([regex]::Matches($script:EditList, '(?m)^- `(Isl\w+)`:') | ForEach-Object {
                $_.Groups[1].Value
            } | Sort-Object -Unique)

        $named.Count | Should-BeGreaterThan 0
        $script:OfferingRules.Count | Should-BeGreaterThan 0
        @($named | Where-Object { $_ -notin $script:OfferingRules }) | Should-BeCollection -Count 0
    }
}
