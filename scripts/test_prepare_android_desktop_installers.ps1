[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot 'prepare_android_desktop_installers.ps1'
$repository = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$buildRoot = [System.IO.Path]::GetFullPath((Join-Path $repository 'build')).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
$testRoot = Join-Path $buildRoot "installer-generator-test-$([guid]::NewGuid().ToString('N'))"
$testRootFull = [System.IO.Path]::GetFullPath($testRoot)
if (-not $testRootFull.StartsWith($buildRoot, [StringComparison]::OrdinalIgnoreCase) -or
    -not [System.IO.Path]::GetFileName($testRootFull).StartsWith('installer-generator-test-', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to create test files outside repository build/: $testRootFull"
}

$version = '4.5.6'
$commit = '0123456789abcdef0123456789abcdef01234567'
$destination = Join-Path $testRoot 'assets/desktop_installers'
$inputs = Join-Path $testRoot 'inputs'
$pubspec = Join-Path $testRoot 'pubspec.yaml'
$windowsName = "LumiaKey-Windows-v$version-Setup.exe"
$macosName = "LumiaKey-macOS-v$version.dmg"
$windowsPath = Join-Path $inputs $windowsName
$macosPath = Join-Path $inputs $macosName
$windowsBytes = [byte[]](0x53, 0x4b, 0x57, 0x49, 0x4e)
$macosBytes = [byte[]](0x53, 0x4b, 0x4d, 0x41, 0x43, 0x4f, 0x53)

function Assert-Throws([scriptblock]$Action, [string]$ExpectedText) {
    try {
        & $Action | Out-Null
    } catch {
        if ($_.Exception.Message -like "*$ExpectedText*") { return }
        throw
    }
    throw "Expected failure containing '$ExpectedText'."
}

try {
    New-Item -ItemType Directory -Force -Path $inputs, $destination | Out-Null
    [System.IO.File]::WriteAllBytes($windowsPath, $windowsBytes)
    [System.IO.File]::WriteAllBytes($macosPath, $macosBytes)
    @(
        'name: test_bundle',
        'flutter:',
        '  assets:',
        '    - assets/desktop_installers/',
        ''
    ) | Set-Content -LiteralPath $pubspec -Encoding utf8

    & $scriptPath -Version $version -Commit $commit `
        -WindowsInstaller $windowsPath -MacDmg $macosPath `
        -Destination $destination -PubspecPath $pubspec | Out-Null
    $catalogPath = Join-Path $destination 'catalog.json'
    $releaseDirectory = Join-Path $destination "releases/$version-$($commit.Substring(0, 12))"
    $catalogBytes = [System.IO.File]::ReadAllBytes($catalogPath)
    $catalog = [System.Text.Encoding]::UTF8.GetString($catalogBytes) | ConvertFrom-Json
    if (@($catalog.installers).Count -ne 2 -or $catalog.commit -cne $commit) {
        throw 'The generator produced incomplete release metadata.'
    }
    foreach ($installer in $catalog.installers) {
        $stagedPath = Join-Path $releaseDirectory $installer.filename
        $sourcePath = if ($installer.platform -eq 'windows') { $windowsPath } else { $macosPath }
        $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
        $stagedHash = (Get-FileHash -LiteralPath $stagedPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($sourceHash -cne $stagedHash -or $installer.sha256 -cne $sourceHash) {
            throw "Staged $($installer.platform) bytes do not match the generated digest."
        }
    }
    $pubspecText = Get-Content -LiteralPath $pubspec -Raw
    $nestedAssetLine = "- assets/desktop_installers/releases/$version-$($commit.Substring(0, 12))/"
    if ([regex]::Matches($pubspecText, [regex]::Escape($nestedAssetLine)).Count -ne 1) {
        throw 'The versioned Flutter asset directory was not registered exactly once.'
    }

    # Same version/commit and exact installer bytes are safe to stage again.
    & $scriptPath -Version $version -Commit $commit `
        -WindowsInstaller $windowsPath -MacDmg $macosPath `
        -Destination $destination -PubspecPath $pubspec | Out-Null
    if ([Convert]::ToBase64String($catalogBytes) -cne
        [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($catalogPath))) {
        throw 'Idempotent staging changed the catalog.'
    }
    $pubspecText = Get-Content -LiteralPath $pubspec -Raw
    if ([regex]::Matches($pubspecText, [regex]::Escape($nestedAssetLine)).Count -ne 1) {
        throw 'Repeated staging duplicated the Flutter asset registration.'
    }

    $secondVersion = '4.5.7'
    $secondReleaseId = "$secondVersion-$($commit.Substring(0, 12))"
    $secondWindows = Join-Path $inputs "LumiaKey-Windows-v$secondVersion-Setup.exe"
    $secondMac = Join-Path $inputs "LumiaKey-macOS-v$secondVersion.dmg"
    [System.IO.File]::WriteAllBytes($secondWindows, $windowsBytes)
    [System.IO.File]::WriteAllBytes($secondMac, $macosBytes)
    & $scriptPath -Version $secondVersion -Commit $commit `
        -WindowsInstaller $secondWindows -MacDmg $secondMac `
        -Destination $destination -PubspecPath $pubspec | Out-Null
    $pubspecText = Get-Content -LiteralPath $pubspec -Raw
    $allReleaseLines = [regex]::Matches($pubspecText, '(?m)^    - assets/desktop_installers/releases/[^\r\n]+')
    if ($allReleaseLines.Count -ne 1 -or
        $allReleaseLines[0].Value -cne "    - assets/desktop_installers/releases/$secondReleaseId/") {
        throw 'Staging a new version did not replace the old exact Flutter asset directory declaration.'
    }

    # A pre-existing release path with any nested content is rejected, even if
    # its two top-level files happen to hash correctly.
    $nestedExtra = Join-Path (Join-Path $destination "releases/$secondReleaseId") 'extra/nested.bin'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $nestedExtra) | Out-Null
    [System.IO.File]::WriteAllBytes($nestedExtra, [byte[]](1))
    $beforeNestedFailure = [System.IO.File]::ReadAllBytes((Join-Path $destination 'catalog.json'))
    Assert-Throws {
        & $scriptPath -Version $secondVersion -Commit $commit `
            -WindowsInstaller $secondWindows -MacDmg $secondMac `
            -Destination $destination -PubspecPath $pubspec
    } 'Existing release asset directory is incomplete'
    if ([Convert]::ToBase64String($beforeNestedFailure) -cne
        [Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Join-Path $destination 'catalog.json')))) {
        throw 'Rejecting nested release content changed the current catalog.'
    }
    Remove-Item -LiteralPath (Join-Path (Join-Path $destination "releases/$secondReleaseId") 'extra') -Recurse -Force

    Assert-Throws {
        & $scriptPath -Version $version -Commit $commit `
            -WindowsInstaller (Join-Path (Join-Path $inputs 'missing') $windowsName) -MacDmg $macosPath `
            -Destination $destination -PubspecPath $pubspec
    } 'Required windows installer is missing'
    Assert-Throws {
        & $scriptPath -Version '4.5' -Commit $commit `
            -WindowsInstaller $windowsPath -MacDmg $macosPath `
            -Destination $destination -PubspecPath $pubspec
    } 'Version must be MAJOR.MINOR.PATCH'
    Assert-Throws {
        & $scriptPath -Version $version -Commit $commit `
            -WindowsInstaller $windowsPath -MacDmg $macosPath `
            -Destination $destination -PubspecPath $pubspec `
            -MaxInstallerSizeBytes 4
    } 'Installer size is outside the allowed range'
    Assert-Throws {
        & $scriptPath -Version $version -Commit $commit `
            -WindowsInstaller $windowsPath -MacDmg $macosPath `
            -Destination $destination -PubspecPath $pubspec `
            -MaxInstallerSizeBytes 536870913
    } 'MaxInstallerSizeBytes must be between'

    $invalidPubspec = Join-Path $testRoot 'invalid-pubspec.yaml'
    [System.IO.File]::WriteAllText($invalidPubspec, "name: no_assets`nflutter:`n  assets:`n")
    $invalidDestination = Join-Path $testRoot 'invalid-pubspec-assets'
    Assert-Throws {
        & $scriptPath -Version '8.8.8' -Commit $commit `
            -WindowsInstaller $windowsPath -MacDmg $macosPath `
            -Destination $invalidDestination -PubspecPath $invalidPubspec
    } 'Flutter pubspec must declare assets/desktop_installers/'
    if (Test-Path -LiteralPath (Join-Path $invalidDestination 'releases')) {
        throw 'Invalid pubspec caused release files to be published before validation.'
    }

    $failureDestination = Join-Path $testRoot 'publish-failure-assets'
    New-Item -ItemType Directory -Force -Path $failureDestination | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $failureDestination 'catalog.json') | Out-Null
    $failurePubspec = Join-Path $testRoot 'publish-failure-pubspec.yaml'
    $failurePubspecOriginal = "name: test_bundle`nflutter:`n  assets:`n    - assets/desktop_installers/`n"
    [System.IO.File]::WriteAllText($failurePubspec, $failurePubspecOriginal)
    $failureWindows = Join-Path $inputs 'LumiaKey-Windows-v8.8.8-Setup.exe'
    $failureMac = Join-Path $inputs 'LumiaKey-macOS-v8.8.8.dmg'
    [System.IO.File]::WriteAllBytes($failureWindows, $windowsBytes)
    [System.IO.File]::WriteAllBytes($failureMac, $macosBytes)
    Assert-Throws {
        & $scriptPath -Version '8.8.8' -Commit $commit `
            -WindowsInstaller $failureWindows -MacDmg $failureMac `
            -Destination $failureDestination -PubspecPath $failurePubspec
    } 'Could not publish installer catalog'
    if (Test-Path -LiteralPath (Join-Path $failureDestination "releases/8.8.8-$($commit.Substring(0, 12))")) {
        throw 'Failed catalog publication left a newly staged release directory behind.'
    }
    if ([System.IO.File]::ReadAllText($failurePubspec) -cne $failurePubspecOriginal) {
        throw 'Failed catalog publication changed the pubspec.'
    }

    # The failed attempts above must not alter the already published output.
    if (-not (Test-Path -LiteralPath (Join-Path $releaseDirectory $windowsName)) -or
        -not (Test-Path -LiteralPath (Join-Path $releaseDirectory $macosName))) {
        throw 'A rejected staging attempt changed the published release files.'
    }
    Write-Output 'PASS: installer generator validates names, versions, sizes, nested content, rollback, hashes, versioned assets, and idempotence.'
} finally {
    if (-not $testRootFull.StartsWith($buildRoot, [StringComparison]::OrdinalIgnoreCase) -or
        -not [System.IO.Path]::GetFileName($testRootFull).StartsWith('installer-generator-test-', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to delete test files outside repository build/: $testRootFull"
    }
    if (Test-Path -LiteralPath $testRootFull) {
        Remove-Item -LiteralPath $testRootFull -Recurse -Force
    }
}
