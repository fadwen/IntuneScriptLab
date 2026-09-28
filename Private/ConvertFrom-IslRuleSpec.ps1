function ConvertFrom-IslRuleSpec {
    <#
    .SYNOPSIS
        Turns a rule hashtable into the parameters of Test-IntuneWin32Rule.

    .DESCRIPTION
        Accepts the shape the Graph API uses for win32LobApp*Rule objects (@odata.type, path,
        fileOrFolderName, operationType, operator, comparisonValue, check32BitOn64System, keyPath,
        valueName, productCode, productVersionOperator, productVersion) and the shorter Type key
        (File, Registry, ProductCode) that the validation kit and -DetectionRule use. Hashtable keys
        are case-insensitive, so camelCase and PascalCase both work.

    .PARAMETER Rule
        The rule hashtable.

    .EXAMPLE
        ConvertFrom-IslRuleSpec -Rule @{ Type = 'File'; Path = 'C:\App'; FileOrFolderName = 'a.exe'
            OperationType = 'exists' }

        @{ Path = 'C:\App'; FileOrFolderName = 'a.exe'; FileOperation = 'exists' }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Rule
    )

    $kind = if ($Rule.Type) { "$($Rule.Type)" }
    elseif ($Rule.'@odata.type' -match '(?i)win32LobApp(FileSystem|Registry|ProductCode|PowerShellScript)') {
        switch ($Matches[1].ToLower()) {
            'filesystem' { 'File' }
            'registry' { 'Registry' }
            'productcode' { 'ProductCode' }
            default { 'Script' }
        }
    }
    else { '' }

    $splat = @{}
    $operator = if ($Rule.Operator) { "$($Rule.Operator)" } else { '' }
    $value = if ($null -ne $Rule.ComparisonValue) { "$($Rule.ComparisonValue)" }
    elseif ($null -ne $Rule.Value) { "$($Rule.Value)" }
    else { $null }

    switch ($kind) {
        'File' {
            $splat.Path = "$($Rule.Path)"
            $splat.FileOrFolderName = "$($Rule.FileOrFolderName)"
            $splat.FileOperation = if ($Rule.OperationType) { "$($Rule.OperationType)" }
            else { "$($Rule.FileOperation)" }
            $splat.Check32BitOn64System = [bool]$Rule.Check32BitOn64System
        }
        'Registry' {
            $splat.KeyPath = "$($Rule.KeyPath)"
            if ($Rule.ValueName) { $splat.ValueName = "$($Rule.ValueName)" }
            $splat.RegistryOperation = if ($Rule.OperationType) { "$($Rule.OperationType)" }
            else { "$($Rule.RegistryOperation)" }
            $splat.Check32BitOn64System = [bool]$Rule.Check32BitOn64System
        }
        'ProductCode' {
            $splat.ProductCode = "$($Rule.ProductCode)"
            if ($Rule.ProductVersionOperator -and "$($Rule.ProductVersionOperator)" -ne 'notConfigured') {
                $operator = "$($Rule.ProductVersionOperator)"
            }
            if ($null -ne $Rule.ProductVersion) { $value = "$($Rule.ProductVersion)" }
        }
        'Script' { throw 'A PowerShell script rule is run with Invoke-IntuneDetectionTest, not evaluated here' }
        default { throw "Rule needs a Type of File, Registry or ProductCode (or a win32LobApp*Rule @odata.type)" }
    }
    if ($operator -and $operator -ne 'notConfigured') { $splat.Operator = $operator }
    if ($null -ne $value) { $splat.Value = $value }
    $splat
}
