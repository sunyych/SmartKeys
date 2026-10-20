[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [Parameter(Mandatory = $true)]
    [string]$Commit,

    [Parameter(Mandatory = $true)]
    [string]$WindowsInstaller,

    [Parameter(Mandatory = $true)]
    [string]$MacDmg,

    [string]$Destination = 'assets/desktop_installers',

    [string]$PubspecPath = 'pubspec.yaml',

    [long]$MaxInstallerSizeBytes = 512L * 1024L * 1024L
)

$ErrorActionPreference = 'Stop'

if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Version must be MAJOR.MINOR.PATCH, got '$Version'."
}
if ($Commit -notmatch '^[0-9a-fA-F]{40}$') {
    throw 'Commit must be a full 40-character Git SHA.'
}
$Commit = $Commit.ToLowerInvariant()
$maxInstallerSize = 512L * 1024L * 1024L
if ($MaxInstallerSizeBytes -le 0 -or $MaxInstallerSizeBytes -gt $maxInstallerSize) {
    throw "MaxInstallerSizeBytes must be between 1 and $maxInstallerSize."
}
$inputs = @(
    [pscustomobject]@{
        platform = 'windows'
        path = $WindowsInstaller
        filename = "LumiaKey-Windows-v$Version-Setup.exe"
    },
    [pscustomobject]@{
        platform = 'macos'
        path = $MacDmg
        filename = "LumiaKey-macOS-v$Version.dmg"
    }
)

$destinationPath = [System.IO.Path]::GetFullPath($Destination)
$releasesPath = Join-Path $destinationPath 'releases'
$stagingParent = Join-Path $destinationPath '.staging'
$releaseId = "$Version-$($Commit.Substring(0, 12))"
$releasePath = Join-Path $releasesPath $releaseId
$stagingPath = Join-Path $stagingParent ([guid]::NewGuid().ToString('N'))
$publishedDirectory = $false
$catalogPublished = $false
$pubspecPublished = $false
$manifestTemp = Join-Path $destinationPath ".catalog-$([guid]::NewGuid().ToString('N')).tmp"
$pubspecFullPath = [System.IO.Path]::GetFullPath($PubspecPath)
$pubspecTemp = "$pubspecFullPath.$([guid]::NewGuid().ToString('N')).tmp"

function Assert-ChildPath([string]$Parent, [string]$Child, [string]$Label) {
    $parentFull = [System.IO.Path]::GetFullPath($Parent).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $childFull = [System.IO.Path]::GetFullPath($Child)
    if (-not $childFull.StartsWith($parentFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label resolves outside its intended parent: $childFull"
    }
}

Assert-ChildPath $destinationPath $releasePath 'Release asset directory'
Assert-ChildPath $destinationPath $stagingPath 'Staging directory'
if (Test-Path -LiteralPath $releasePath) {
    $releaseRootItem = Get-Item -LiteralPath $releasePath -Force
    if (($releaseRootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Existing release asset directory cannot be a symbolic link: $releasePath"
    }
}

if (-not (Test-Path -LiteralPath $pubspecFullPath -PathType Leaf)) {
    throw "Flutter pubspec was not found: $pubspecFullPath"
}
$originalPubspecBytes = [System.IO.File]::ReadAllBytes($pubspecFullPath)
$pubspecText = [System.Text.Encoding]::UTF8.GetString($originalPubspecBytes)
if ($pubspecText -notmatch '(?m)^flutter:\s*\r?\n') {
    throw 'Flutter pubspec has no flutter section.'
}
if ($pubspecText -notmatch '(?m)^  assets:\s*\r?\n') {
    throw 'Flutter pubspec has no flutter.assets list.'
}
$baseAssetLine = '    - assets/desktop_installers/'
if ($pubspecText -notmatch ('(?m)^' + [regex]::Escape($baseAssetLine) + '\s*$')) {
    throw 'Flutter pubspec must declare assets/desktop_installers/.'
}
$relativeAssetDirectory = "assets/desktop_installers/releases/$releaseId/"
$assetLine = "    - $relativeAssetDirectory"
# A fresh run must bundle only its release's nested directory. Previous release
# directories remain on disk for reproducibility but are not embedded again.
$pubspecText = [regex]::Replace(
    $pubspecText,
    '(?m)^    - assets/desktop_installers/releases/\d+\.\d+\.\d+-[0-9a-f]{12}/\s*\r?\n?',
    ''
)
if ($pubspecText -notmatch ('(?m)^' + [regex]::Escape($assetLine) + '\s*$')) {
    $pubspecText = [regex]::Replace(
        $pubspecText,
        '(?m)^' + [regex]::Escape($baseAssetLine) + '\s*$' ,
        [System.Text.RegularExpressions.MatchEvaluator]{ param($match) "$($match.Value)`r`n$assetLine" },
        1
    )
}

try {
    $entries = [System.Collections.Generic.List[object]]::new()
    New-Item -ItemType Directory -Force -Path $stagingPath | Out-Null

    foreach ($input in $inputs) {
        $sourcePath = [System.IO.Path]::GetFullPath($input.path)
        if ([System.IO.Path]::GetFileName($sourcePath) -cne $input.filename) {
            throw "Unexpected $($input.platform) installer filename '$([System.IO.Path]::GetFileName($sourcePath))'; expected '$($input.filename)'."
        }
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Required $($input.platform) installer is missing: $sourcePath"
        }
        $sourceItem = Get-Item -LiteralPath $sourcePath -Force
        if (($sourceItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Installer input cannot be a symbolic link: $sourcePath"
        }
        if ($sourceItem.Length -le 0 -or $sourceItem.Length -gt $MaxInstallerSizeBytes) {
            throw "Installer size is outside the allowed range: $($sourceItem.Length) bytes."
        }

        $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($sourceHash -notmatch '^[0-9a-f]{64}$') {
            throw "Could not calculate a complete SHA-256 for $sourcePath"
        }
        $stagedFile = Join-Path $stagingPath $input.filename
        Copy-Item -LiteralPath $sourcePath -Destination $stagedFile
        $stagedItem = Get-Item -LiteralPath $stagedFile
        $stagedHash = (Get-FileHash -LiteralPath $stagedFile -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($stagedItem.Length -ne $sourceItem.Length -or $stagedHash -cne $sourceHash) {
            throw "Copied $($input.platform) installer failed size/hash verification."
        }

        $entries.Add([ordered]@{
            platform = $input.platform
            filename = $input.filename
            assetPath = "assets/desktop_installers/releases/$releaseId/$($input.filename)"
            sizeBytes = [long]$sourceItem.Length
            sha256 = $sourceHash
        })
    }

    if (Test-Path -LiteralPath $releasePath) {
        $existingItems = @(Get-ChildItem -LiteralPath $releasePath -Force -Recurse)
        $existingFiles = @($existingItems | Where-Object { -not $_.PSIsContainer })
        $hasUnsafeItems = @($existingItems | Where-Object {
            $_.PSIsContainer -or (($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
        }).Count -gt 0
        if ($hasUnsafeItems -or $existingFiles.Count -ne $inputs.Count) {
            throw "Existing release asset directory is incomplete: $releasePath"
        }
        foreach ($entry in $entries) {
            $existing = Join-Path $releasePath $entry.filename
            if (-not (Test-Path -LiteralPath $existing -PathType Leaf)) {
                throw "Existing release asset is missing: $existing"
            }
            $existingItem = Get-Item -LiteralPath $existing
            $existingHash = (Get-FileHash -LiteralPath $existing -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($existingItem.Length -ne $entry.sizeBytes -or $existingHash -cne $entry.sha256) {
                throw "Existing release assets for $releaseId differ from this run; refusing to replace them."
            }
        }
    } else {
        New-Item -ItemType Directory -Force -Path $releasesPath | Out-Null
        # Both staging and destination are below the same assets directory, so this
        # directory rename publishes the complete pair in one filesystem operation.
        [System.IO.Directory]::Move($stagingPath, $releasePath)
        $publishedDirectory = $true
    }

    $manifest = [ordered]@{
        schemaVersion = 1
        version = $Version
        commit = $Commit
        installers = @($entries)
    }
    $manifestJson = $manifest | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText(
        $manifestTemp,
        $manifestJson + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false)
    )
    [System.IO.File]::WriteAllText($pubspecTemp, $pubspecText, [System.Text.UTF8Encoding]::new($false))

    $manifestPath = Join-Path $destinationPath 'catalog.json'
    $oldCatalogBytes = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) { [System.IO.File]::ReadAllBytes($manifestPath) } else { $null }
    # Publish each file by same-directory rename. If a later rename fails, the
    # catch block restores the prior catalog and pubspec and removes only this
    # run's newly-created release directory.
    try {
        [System.IO.File]::Move($manifestTemp, $manifestPath, $true)
    } catch {
        throw "Could not publish installer catalog: $($_.Exception.Message)"
    }
    $catalogPublished = $true
    [System.IO.File]::Move($pubspecTemp, $pubspecFullPath, $true)
    $pubspecPublished = $true

    Write-Output "Published $($entries.Count) verified installers for $Version ($Commit) to $manifestPath and registered $relativeAssetDirectory in Flutter assets."
} catch {
    $manifestPath = Join-Path $destinationPath 'catalog.json'
    if ($catalogPublished) {
        if ($null -eq $oldCatalogBytes) {
            if (Test-Path -LiteralPath $manifestPath) { Remove-Item -LiteralPath $manifestPath -Force }
        } else {
            [System.IO.File]::WriteAllBytes($manifestPath, $oldCatalogBytes)
        }
    }
    if ($pubspecPublished) {
        [System.IO.File]::WriteAllBytes($pubspecFullPath, $originalPubspecBytes)
    }
    if ($publishedDirectory -and (Test-Path -LiteralPath $releasePath)) {
        Assert-ChildPath $destinationPath $releasePath 'Rollback release directory'
        Remove-Item -LiteralPath $releasePath -Recurse -Force
    }
    throw
} finally {
    if (-not $publishedDirectory -and (Test-Path -LiteralPath $stagingPath)) {
        Assert-ChildPath $destinationPath $stagingPath 'Staging cleanup directory'
        Remove-Item -LiteralPath $stagingPath -Recurse -Force
    }
    foreach ($temporary in @($manifestTemp, $pubspecTemp)) {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}
