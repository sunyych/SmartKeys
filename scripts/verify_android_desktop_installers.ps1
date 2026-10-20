[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ApkPath,

    [Parameter(Mandatory = $true)]
    [string]$CatalogPath,

    [long]$MaxInstallerSizeBytes = 512L * 1024L * 1024L
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Read-ZipEntryText {
    param([System.IO.Compression.ZipArchiveEntry]$Entry)
    $stream = $Entry.Open()
    try {
        $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8, $true)
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally {
        if ($stream) { $stream.Dispose() }
    }
}

$apkFullPath = [System.IO.Path]::GetFullPath($ApkPath)
$catalogFullPath = [System.IO.Path]::GetFullPath($CatalogPath)
if ($MaxInstallerSizeBytes -le 0 -or $MaxInstallerSizeBytes -gt 512L * 1024L * 1024L) {
    throw 'MaxInstallerSizeBytes must be between 1 and 536870912.'
}
if (-not (Test-Path -LiteralPath $apkFullPath -PathType Leaf)) { throw "APK does not exist: $apkFullPath" }
if (-not (Test-Path -LiteralPath $catalogFullPath -PathType Leaf)) { throw "Expected catalog does not exist: $catalogFullPath" }

$expected = Get-Content -LiteralPath $catalogFullPath -Raw | ConvertFrom-Json
if ($expected.schemaVersion -ne 1 -or $expected.version -notmatch '^\d+\.\d+\.\d+$' -or
    $expected.commit -notmatch '^[0-9a-f]{40}$') {
    throw 'Expected catalog has an invalid schema, version, or commit.'
}
$installers = @($expected.installers)
if ($installers.Count -ne 2) { throw 'Expected catalog must contain exactly the Windows and macOS installers.' }
$releaseId = "$($expected.version)-$($expected.commit.Substring(0, 12))"
$seen = @{}
foreach ($installer in $installers) {
    $platform = [string]$installer.platform
    if ($platform -cnotin @('windows', 'macos') -or $seen.ContainsKey($platform)) {
        throw "Unexpected or duplicate installer platform: $platform"
    }
    $seen[$platform] = $true
    $expectedFile = if ($platform -ceq 'windows') {
        "LumiaKey-Windows-v$($expected.version)-Setup.exe"
    } else {
        "LumiaKey-macOS-v$($expected.version).dmg"
    }
    $expectedAssetPath = "assets/desktop_installers/releases/$releaseId/$expectedFile"
    if ([string]$installer.filename -cne $expectedFile -or
        [string]$installer.assetPath -cne $expectedAssetPath) {
        throw "Unexpected $platform filename or asset path in expected catalog."
    }
    if ([long]$installer.sizeBytes -le 0 -or [long]$installer.sizeBytes -gt $MaxInstallerSizeBytes -or
        [string]$installer.sha256 -cnotmatch '^[0-9a-f]{64}$') {
        throw "Invalid size or SHA-256 metadata for $expectedFile."
    }
}
if (-not $seen.ContainsKey('windows') -or -not $seen.ContainsKey('macos')) {
    throw 'Expected catalog must contain one Windows and one macOS installer.'
}

$archive = [System.IO.Compression.ZipFile]::OpenRead($apkFullPath)
try {
    $releasePrefix = 'assets/flutter_assets/assets/desktop_installers/releases/'
    $expectedZipNames = @(
        foreach ($item in $installers) { "assets/flutter_assets/$($item.assetPath)" }
    )
    $releaseEntries = @($archive.Entries | Where-Object { $_.FullName.StartsWith($releasePrefix, [StringComparison]::Ordinal) })
    foreach ($entryGroup in @($releaseEntries | Group-Object FullName)) {
        if ($entryGroup.Count -ne 1) { throw "APK contains duplicate installer ZIP entry: $($entryGroup.Name)" }
    }
    $unexpectedReleaseEntries = @($releaseEntries | Where-Object { $_.FullName -cnotin $expectedZipNames })
    if ($unexpectedReleaseEntries.Count -gt 0) {
        throw "APK contains unlisted installer files under the release asset directory: $($unexpectedReleaseEntries[0].FullName)"
    }
    $catalogEntryName = 'assets/flutter_assets/assets/desktop_installers/catalog.json'
    if (@($archive.Entries | Where-Object { $_.FullName -ceq $catalogEntryName }).Count -ne 1) {
        throw 'APK must contain exactly one installer catalog entry.'
    }
    $catalogEntry = $archive.GetEntry($catalogEntryName)
    if ($null -eq $catalogEntry) { throw "Installer catalog is missing from APK: $catalogEntryName" }
    $embedded = Read-ZipEntryText $catalogEntry | ConvertFrom-Json
    if ($embedded.schemaVersion -ne $expected.schemaVersion -or
        [string]$embedded.version -cne [string]$expected.version -or
        [string]$embedded.commit -cne [string]$expected.commit) {
        throw 'APK-embedded catalog release metadata differs from the expected catalog.'
    }
    $embeddedInstallers = @($embedded.installers)
    if ($embeddedInstallers.Count -ne $installers.Count) {
        throw 'APK-embedded catalog installer count differs from the expected catalog.'
    }
    foreach ($item in $installers) {
        $matches = @($embeddedInstallers | Where-Object {
            [string]$_.platform -ceq [string]$item.platform
        })
        if ($matches.Count -ne 1) { throw "APK catalog is missing or duplicates $($item.platform)." }
        $actual = $matches[0]
        foreach ($field in @('filename', 'assetPath', 'sha256')) {
            if ([string]$actual.$field -cne [string]$item.$field) {
                throw "APK-embedded catalog $field mismatch for $($item.platform)."
            }
        }
        if ([long]$actual.sizeBytes -ne [long]$item.sizeBytes) {
            throw "APK-embedded catalog size mismatch for $($item.platform)."
        }

        $zipName = "assets/flutter_assets/$($item.assetPath)"
        if (@($archive.Entries | Where-Object { $_.FullName -ceq $zipName }).Count -ne 1) {
            throw "APK must contain exactly one nested installer entry: $zipName"
        }
        $entry = $archive.GetEntry($zipName)
        if ($null -eq $entry) { throw "Nested installer is missing from APK: $zipName" }
        if ($entry.Length -ne [long]$item.sizeBytes) {
            throw "Nested installer size mismatch for $($item.filename)."
        }
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $stream = $entry.Open()
        try { $digest = [Convert]::ToHexString($sha.ComputeHash($stream)).ToLowerInvariant() }
        finally { $stream.Dispose(); $sha.Dispose() }
        if ($digest -cne [string]$item.sha256) {
            throw "Nested installer SHA-256 mismatch for $($item.filename)."
        }
    }
} finally {
    $archive.Dispose()
}

Write-Output "PASS: $apkFullPath embeds the expected $($expected.version) catalog and verified Windows/macOS installers."
