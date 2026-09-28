# Win32 app packaging and content upload, dot-sourced by Invoke-ValidationRound.ps1.
# Requires an active Microsoft Graph connection for Publish-Win32AppContent.

function New-IntuneWinPackage {
    # Wraps Microsoft's IntuneWinAppUtil.exe (signed, from github.com/microsoft/Microsoft-Win32-Content-Prep-Tool).
    # A build step into a scratch folder; the deploying caller is the one that supports -WhatIf.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param(
        [Parameter(Mandatory)][string]$ToolPath,
        [Parameter(Mandatory)][string]$SourceFolder,
        [Parameter(Mandatory)][string]$SetupFile,
        [Parameter(Mandatory)][string]$OutputFolder
    )
    $null = New-Item -ItemType Directory -Path $OutputFolder -Force
    $packageName = [IO.Path]::GetFileNameWithoutExtension($SetupFile) + '.intunewin'
    $package = Join-Path -Path $OutputFolder -ChildPath $packageName
    if (Test-Path -Path $package) { Remove-Item -Path $package }
    & $ToolPath -c $SourceFolder -s $SetupFile -o $OutputFolder -q | Out-Null
    if (-not (Test-Path -Path $package)) { throw "IntuneWinAppUtil did not produce $package" }
    Get-Item -Path $package
}

function Get-IntuneWinContent {
    # A .intunewin is a zip: the encrypted payload under Contents\ and its keys in Metadata\Detection.xml.
    # Graph wants the payload uploaded as-is plus the encryption info from the XML.
    param(
        [Parameter(Mandatory)][string]$PackagePath,
        [Parameter(Mandatory)][string]$WorkFolder
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
    # An MSI setup file carries its product metadata in the same XML; Graph wants it as msiInformation
    $msi = if ($info.MsiInfo) {
        @{
            '@odata.type'  = '#microsoft.graph.win32LobAppMsiInformation'
            productCode    = $info.MsiInfo.MsiProductCode
            productVersion = $info.MsiInfo.MsiProductVersion
            upgradeCode    = $info.MsiInfo.MsiUpgradeCode
            requiresReboot = ($info.MsiInfo.MsiRequiresReboot -eq 'true')
            packageType    = switch ("$($info.MsiInfo.MsiExecutionContext)") {
                'User' { 'perUser' } 'Any' { 'dualPurpose' } default { 'perMachine' }
            }
            productName    = "$($info.MsiInfo.MsiProductName)"
            publisher      = "$($info.MsiInfo.MsiPublisher)"
        }
    }
    else { $null }
    [pscustomobject]@{
        FileName        = $info.FileName
        SetupFile       = $info.SetupFile
        MsiInformation  = $msi
        UnencryptedSize = [int64]$info.UnencryptedContentSize
        EncryptedPath   = $encryptedPath
        EncryptedSize   = (Get-Item -Path $encryptedPath).Length
        EncryptionInfo  = @{
            '@odata.type'        = '#microsoft.graph.fileEncryptionInfo'
            encryptionKey        = $e.EncryptionKey
            macKey               = $e.MacKey
            initializationVector = $e.InitializationVector
            mac                  = $e.Mac
            profileIdentifier    = $e.ProfileIdentifier
            fileDigest           = $e.FileDigest
            fileDigestAlgorithm  = $e.FileDigestAlgorithm
        }
    }
}

function Wait-MobileAppContentFile {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$State,
        [int]$TimeoutSeconds = 180
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $file = Invoke-MgGraphRequest -Method GET -Uri $Uri
        if ($file.uploadState -eq $State) { return $file }
        if ($file.uploadState -match 'Failed|TimedOut') { throw "Content file upload state: $($file.uploadState)" }
        Start-Sleep -Seconds 3
    } while ((Get-Date) -lt $deadline)
    throw "Timed out waiting for content file state $State (last: $($file.uploadState))"
}

function Publish-Win32AppContent {
    # Content version -> file entry -> block-blob upload to the SAS URI Intune hands back -> commit -> set as
    # current.
    param(
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][pscustomobject]$Content
    )
    $versions = "/beta/deviceAppManagement/mobileApps/$AppId/microsoft.graph.win32LobApp/contentVersions"
    $version = Invoke-MgGraphRequest -Method POST -Uri $versions -Body @{}
    $file = Invoke-MgGraphRequest -Method POST -Uri "$versions/$($version.id)/files" -Body @{
        '@odata.type' = '#microsoft.graph.mobileAppContentFile'
        name          = $Content.FileName
        size          = $Content.UnencryptedSize
        sizeEncrypted = $Content.EncryptedSize
        manifest      = $null
        isDependency  = $false
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
        $blockSplat = @{
            Method = 'PUT'; Uri = $blockUri; Headers = @{ 'x-ms-blob-type' = 'BlockBlob' }; Body = $body
        }
        Invoke-WebRequest @blockSplat | Out-Null
        $id
    }
    $blockList = '<?xml version="1.0" encoding="utf-8"?><BlockList>' +
        (($blockIds | ForEach-Object { "<Latest>$_</Latest>" }) -join '') + '</BlockList>'
    $listSplat = @{
        Method = 'PUT'; Uri = "$($file.azureStorageUri)&comp=blocklist"; Body = $blockList
        ContentType = 'text/xml'
    }
    Invoke-WebRequest @listSplat | Out-Null

    $commitBody = @{ fileEncryptionInfo = $Content.EncryptionInfo }
    Invoke-MgGraphRequest -Method POST -Uri "$fileUri/commit" -Body $commitBody | Out-Null
    Wait-MobileAppContentFile -Uri $fileUri -State 'commitFileSuccess' | Out-Null
    Invoke-MgGraphRequest -Method PATCH -Uri "/beta/deviceAppManagement/mobileApps/$AppId" -Body @{
        '@odata.type'           = '#microsoft.graph.win32LobApp'
        committedContentVersion = $version.id
    } | Out-Null
}
