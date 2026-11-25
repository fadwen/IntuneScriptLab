# Win32 app packaging and content upload, dot-sourced by Invoke-ValidationRound.ps1.
# Requires an active Microsoft Graph connection for Publish-Win32AppContent.


function New-IntuneWinPackage {
    <#
    .SYNOPSIS
    Packages a setup folder as a .intunewin file with IntuneWinAppUtil.exe.

    .DESCRIPTION
    Wraps Microsoft's IntuneWinAppUtil.exe (signed, from
    github.com/microsoft/Microsoft-Win32-Content-Prep-Tool). A build step into a scratch folder;
    the deploying caller is the one that supports -WhatIf. A package of the same name in the output
    folder is replaced. The function ends with an error when the tool produced no package.

    .PARAMETER ToolPath
    The full path of IntuneWinAppUtil.exe. The caller checks its signature before it calls this.

    .PARAMETER SourceFolder
    The folder whose content goes into the package.

    .PARAMETER SetupFile
    The setup file in the source folder, by name, such as install.ps1. The package is named after
    it.

    .PARAMETER OutputFolder
    The folder the package is written to. It is created when it does not exist.

    .EXAMPLE
    New-IntuneWinPackage -ToolPath $toolPath -SourceFolder $source -SetupFile 'install.ps1' -OutputFolder $out

    Packages the source folder as install.intunewin in the output folder.

    .INPUTS
    None.

    .OUTPUTS
    System.IO.FileInfo. The package that the tool wrote.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [string]$ToolPath,

        [Parameter(Mandatory)]
        [string]$SourceFolder,

        [Parameter(Mandatory)]
        [string]$SetupFile,

        [Parameter(Mandatory)]
        [string]$OutputFolder
    )

    $null = New-Item -ItemType Directory -Path $OutputFolder -Force
    $packageName = [IO.Path]::GetFileNameWithoutExtension($SetupFile) + '.intunewin'
    $package = Join-Path -Path $OutputFolder -ChildPath $packageName
    if (Test-Path -LiteralPath $package) { Remove-Item -LiteralPath $package }
    & $ToolPath -c $SourceFolder -s $SetupFile -o $OutputFolder -q | Out-Null
    if (-not (Test-Path -LiteralPath $package)) {
        $exception = [System.IO.FileNotFoundException]::new("IntuneWinAppUtil did not produce $package", $package)
        $category = [System.Management.Automation.ErrorCategory]::ObjectNotFound
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception, 'IntuneWinPackageNotProduced', $category, $package)
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }
    Get-Item -LiteralPath $package
}


function Get-IntuneWinXmlValue {
    <#
    .SYNOPSIS
    Gets a child element's value, or nothing when the element has no such child.

    .DESCRIPTION
    Returns what member access on the element returns for the child: its text for an element
    that holds only text, and the element itself otherwise. A child that is not there gives $null
    instead of the error that member access raises under strict mode.

    .PARAMETER Element
    The XML element whose child is read.

    .PARAMETER Name
    The name of the child element.

    .EXAMPLE
    Get-IntuneWinXmlValue -Element $msiInfo -Name 'MsiPublisher'

    Gets the publisher from the MsiInfo element of a package's Detection.xml.

    .INPUTS
    None.

    .OUTPUTS
    System.Object. The child's text or element, or $null.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [System.Xml.XmlElement]$Element,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $Element.SelectSingleNode($Name)) {
        return $null
    }
    $Element.$Name
}


function Get-IntuneWinContent {
    <#
    .SYNOPSIS
    Extracts the encrypted payload and its encryption info from a .intunewin file.

    .DESCRIPTION
    A .intunewin is a zip: the encrypted payload under Contents\ and its keys in
    Metadata\Detection.xml. Graph wants the payload uploaded as-is plus the encryption info from
    the XML. The payload is extracted into the work folder, replacing a file of the same name. An
    MSI setup file carries its product metadata in the same XML, which is returned as the
    msiInformation that Graph takes.

    .PARAMETER PackagePath
    The full path of the .intunewin package.

    .PARAMETER WorkFolder
    The folder the encrypted payload is extracted to.

    .EXAMPLE
    Get-IntuneWinContent -PackagePath $package.FullName -WorkFolder $build

    Extracts the payload of the package into the build folder and reads its encryption info.

    .INPUTS
    None.

    .OUTPUTS
    IntuneScriptLab.Validation.IntuneWinContent. The payload's file name, path and sizes, the setup
    file, the encryption info and the MSI information, for Publish-Win32AppContent.
    #>
    [CmdletBinding()]
    [OutputType('IntuneScriptLab.Validation.IntuneWinContent')]
    param(
        [Parameter(Mandatory)]
        [string]$PackagePath,

        [Parameter(Mandatory)]
        [string]$WorkFolder
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($PackagePath)
    try {
        $xmlEntry = $zip.Entries | Where-Object { $_.FullName -eq 'IntuneWinPackage/Metadata/Detection.xml' }
        $reader = [IO.StreamReader]::new($xmlEntry.Open())
        [xml]$xml = $reader.ReadToEnd()
        $reader.Dispose()
        $info = $xml.ApplicationInfo
        $inner = $zip.Entries | Where-Object { $_.FullName -eq "IntuneWinPackage/Contents/$($info.FileName)" }
        $encryptedPath = Join-Path -Path $WorkFolder -ChildPath $info.FileName
        [IO.Compression.ZipFileExtensions]::ExtractToFile($inner, $encryptedPath, $true)
    }
    finally { $zip.Dispose() }

    $e = $info.EncryptionInfo
    # An MSI setup file carries its product metadata in the same XML; Graph wants it as msiInformation.
    # A package of a script has no MsiInfo element, and the MSI fields are read the same way.
    $msiInfo = Get-IntuneWinXmlValue -Element $info -Name 'MsiInfo'
    $msi = if ($msiInfo) {
        $msiExecutionContext = Get-IntuneWinXmlValue -Element $msiInfo -Name 'MsiExecutionContext'
        @{
            '@odata.type' = '#microsoft.graph.win32LobAppMsiInformation'
            productCode = Get-IntuneWinXmlValue -Element $msiInfo -Name 'MsiProductCode'
            productVersion = Get-IntuneWinXmlValue -Element $msiInfo -Name 'MsiProductVersion'
            upgradeCode = Get-IntuneWinXmlValue -Element $msiInfo -Name 'MsiUpgradeCode'
            requiresReboot = ((Get-IntuneWinXmlValue -Element $msiInfo -Name 'MsiRequiresReboot') -eq 'true')
            packageType = switch ("$msiExecutionContext") {
                'User' { 'perUser' } 'Any' { 'dualPurpose' } default { 'perMachine' }
            }
            productName = "$(Get-IntuneWinXmlValue -Element $msiInfo -Name 'MsiProductName')"
            publisher = "$(Get-IntuneWinXmlValue -Element $msiInfo -Name 'MsiPublisher')"
        }
    }
    else { $null }
    [pscustomobject]@{
        PSTypeName = 'IntuneScriptLab.Validation.IntuneWinContent'
        FileName = $info.FileName
        SetupFile = $info.SetupFile
        MsiInformation = $msi
        UnencryptedSize = [int64]$info.UnencryptedContentSize
        EncryptedPath = $encryptedPath
        EncryptedSize = (Get-Item -LiteralPath $encryptedPath).Length
        EncryptionInfo = @{
            '@odata.type' = '#microsoft.graph.fileEncryptionInfo'
            encryptionKey = $e.EncryptionKey
            macKey = $e.MacKey
            initializationVector = $e.InitializationVector
            mac = $e.Mac
            profileIdentifier = $e.ProfileIdentifier
            fileDigest = $e.FileDigest
            fileDigestAlgorithm = $e.FileDigestAlgorithm
        }
    }
}


function Wait-MobileAppContentFile {
    <#
    .SYNOPSIS
    Waits until an Intune content file reaches an upload state, and returns it.

    .DESCRIPTION
    Reads the content file from Graph every three seconds until its uploadState is the state
    asked for, and returns the file as Graph gave it. A state that names a failure or a timeout,
    and a wait longer than the timeout, end the function with an error.

    .PARAMETER Uri
    The Graph address of the content file, relative to the Graph root.

    .PARAMETER State
    The uploadState to wait for, such as azureStorageUriRequestSuccess or commitFileSuccess.

    .PARAMETER TimeoutSeconds
    How long to wait for the state. Default 180.

    .EXAMPLE
    Wait-MobileAppContentFile -Uri $fileUri -State 'commitFileSuccess'

    Waits until Intune has committed the uploaded content.

    .INPUTS
    None.

    .OUTPUTS
    System.Collections.Hashtable. The content file as Invoke-MgGraphRequest returned it.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [string]$State,

        [int]$TimeoutSeconds = 180
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $file = Invoke-MgGraphRequest -Method GET -Uri $Uri
        if ($file.uploadState -eq $State) { return $file }
        if ($file.uploadState -match 'Failed|TimedOut') {
            $exception = [System.InvalidOperationException]::new("Content file upload state: $($file.uploadState)")
            $category = [System.Management.Automation.ErrorCategory]::InvalidResult
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception, 'ContentFileUploadFailed', $category, $Uri)
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
        Start-Sleep -Seconds 3
    } while ((Get-Date) -lt $deadline)
    $message = "Timed out waiting for content file state $State (last: $($file.uploadState))"
    $exception = [System.TimeoutException]::new($message)
    $category = [System.Management.Automation.ErrorCategory]::OperationTimeout
    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
        $exception, 'ContentFileStateTimedOut', $category, $Uri)
    $PSCmdlet.ThrowTerminatingError($errorRecord)
}


function Publish-Win32AppContent {
    <#
    .SYNOPSIS
    Uploads encrypted package content to an Intune Win32 app and makes it current.

    .DESCRIPTION
    Content version -> file entry -> block-blob upload to the SAS URI Intune hands back -> commit
    -> set as current. The payload is uploaded in blocks of 4 MB, then the block list, and the
    commit carries the encryption info. Needs an active Microsoft Graph connection. Any failure
    ends the function with its error; an app version left without committed content stays in the
    tenant.

    .PARAMETER AppId
    The id of the Win32 app in Intune.

    .PARAMETER Content
    The package content, as Get-IntuneWinContent returns it.

    .EXAMPLE
    Publish-Win32AppContent -AppId $app.id -Content $content

    Uploads the content to the app that was just created.

    .INPUTS
    None.

    .OUTPUTS
    None.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$AppId,

        [Parameter(Mandatory)]
        [pscustomobject]$Content
    )

    try {
        $versions = "/beta/deviceAppManagement/mobileApps/$AppId/microsoft.graph.win32LobApp/contentVersions"
        $version = Invoke-MgGraphRequest -Method POST -Uri $versions -Body @{}
        $file = Invoke-MgGraphRequest -Method POST -Uri "$versions/$($version.id)/files" -Body @{
            '@odata.type' = '#microsoft.graph.mobileAppContentFile'
            name = $Content.FileName
            size = $Content.UnencryptedSize
            sizeEncrypted = $Content.EncryptedSize
            manifest = $null
            isDependency = $false
        }
        $fileUri = "$versions/$($version.id)/files/$($file.id)"
        $file = Wait-MobileAppContentFile -Uri $fileUri -State 'azureStorageUriRequestSuccess'

        $bytes = [IO.File]::ReadAllBytes($Content.EncryptedPath)
        $chunk = 4MB
        $blockIds = for ($i = 0; $i * $chunk -lt $bytes.Length; $i++) {
            $id = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(('block-{0:D6}' -f $i)))
            $length = [Math]::Min($chunk, $bytes.Length - $i * $chunk)
            $body = [byte[]]::new($length)
            [Array]::Copy($bytes, $i * $chunk, $body, 0, $length)
            $blockUri = "$($file.azureStorageUri)&comp=block&blockid=$([uri]::EscapeDataString($id))"
            # The address is a signed blob address; the request carries no credential header
            $blockSplat = @{
                Method = 'PUT'; Uri = $blockUri; Headers = @{ 'x-ms-blob-type' = 'BlockBlob' }; Body = $body
                MaximumRedirection = 0
            }
            Invoke-WebRequest @blockSplat | Out-Null
            $id
        }
        $blockList = '<?xml version="1.0" encoding="utf-8"?><BlockList>' +
            (($blockIds | ForEach-Object { "<Latest>$_</Latest>" }) -join '') + '</BlockList>'
        # The address is a signed blob address; the request carries no credential header
        $listSplat = @{
            Method = 'PUT'; Uri = "$($file.azureStorageUri)&comp=blocklist"; Body = $blockList
            ContentType = 'text/xml'; MaximumRedirection = 0
        }
        Invoke-WebRequest @listSplat | Out-Null

        $commitBody = @{ fileEncryptionInfo = $Content.EncryptionInfo }
        Invoke-MgGraphRequest -Method POST -Uri "$fileUri/commit" -Body $commitBody | Out-Null
        Wait-MobileAppContentFile -Uri $fileUri -State 'commitFileSuccess' | Out-Null
        Invoke-MgGraphRequest -Method PATCH -Uri "/beta/deviceAppManagement/mobileApps/$AppId" -Body @{
            '@odata.type' = '#microsoft.graph.win32LobApp'
            committedContentVersion = $version.id
        } | Out-Null
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
