[CmdletBinding()]
param(
    [string]$Flutter = 'flutter',
    [switch]$SkipApkBuild
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$repository = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$assets = Join-Path $repository 'assets/desktop_installers'
$pubspec = Join-Path $repository 'pubspec.yaml'
$version = '97.1.0'
$commit = 'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678'
$releaseId = "$version-$($commit.Substring(0, 12))"
$releaseDirectory = Join-Path $assets "releases/$releaseId"
$catalogPath = Join-Path $assets 'catalog.json'
$testRoot = Join-Path $repository "build/installer-bundle-test-$([guid]::NewGuid().ToString('N'))"
$fixtureDirectory = Join-Path $testRoot 'fixtures'
$outputDirectory = Join-Path $testRoot 'apk'
$testApkPath = Join-Path $outputDirectory 'app-debug.apk'
$defaultApkPath = Join-Path $repository 'build/app/outputs/flutter-apk/app-debug.apk'

if ((Test-Path -LiteralPath $releaseDirectory) -or
    (Test-Path -LiteralPath $catalogPath)) {
    throw 'Refusing to overwrite existing generated installer assets.'
}

$originalPubspecBytes = [System.IO.File]::ReadAllBytes($pubspec)
New-Item -ItemType Directory -Force -Path $fixtureDirectory | Out-Null
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$windowsPath = Join-Path $fixtureDirectory "LumiaKey-Windows-v$version-Setup.exe"
$macosPath = Join-Path $fixtureDirectory "LumiaKey-macOS-v$version.dmg"
[bool]$buildWasRun = $false
[System.IO.File]::WriteAllBytes($windowsPath, [byte[]](0x4c, 0x55, 0x4d, 0x49, 0x41, 0x57))
[System.IO.File]::WriteAllBytes($macosPath, [byte[]](0x4c, 0x55, 0x4d, 0x49, 0x41, 0x4d, 0x41))

try {
    & (Join-Path $PSScriptRoot 'prepare_android_desktop_installers.ps1') `
        -Version $version `
        -Commit $commit `
        -WindowsInstaller $windowsPath `
        -MacDmg $macosPath `
        -Destination $assets `
        -PubspecPath $pubspec

    $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
    if ($catalog.version -ne $version -or $catalog.commit -ne $commit -or
        @($catalog.installers).Count -ne 2) {
        throw 'The generated release catalog has unexpected metadata.'
    }

    if ($SkipApkBuild) {
        Write-Output 'PASS: temporary installer fixtures and exact nested Flutter asset registration validated; APK build skipped.'
        return
    }

    $hadPreviousApk = Test-Path -LiteralPath $defaultApkPath -PathType Leaf
    $previousApk = Join-Path $testRoot 'previous-app-debug.apk'
    if ($hadPreviousApk) {
        Copy-Item -LiteralPath $defaultApkPath -Destination $previousApk
    }
    $buildWasRun = $true
    & $Flutter build apk --debug --target-platform android-arm64 --no-pub
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter debug APK build failed with exit code $LASTEXITCODE."
    }
    if (-not (Test-Path -LiteralPath $defaultApkPath -PathType Leaf)) {
        throw "Flutter did not produce the expected debug APK: $defaultApkPath"
    }
    Copy-Item -LiteralPath $defaultApkPath -Destination $testApkPath -Force

    & (Join-Path $PSScriptRoot 'verify_android_desktop_installers.ps1') `
        -ApkPath $testApkPath `
        -CatalogPath $catalogPath

    Write-Output "PASS: the test-only debug APK includes the catalog and both nested installer assets with matching sizes and SHA-256 values: $testApkPath"
} finally {
    [System.IO.File]::WriteAllBytes($pubspec, $originalPubspecBytes)
    $assetsFull = [System.IO.Path]::GetFullPath($assets).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $releaseFull = [System.IO.Path]::GetFullPath($releaseDirectory)
    if (-not $releaseFull.StartsWith($assetsFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to delete a release directory outside installer assets: $releaseFull"
    }
    if (Test-Path -LiteralPath $releaseDirectory) {
        Remove-Item -LiteralPath $releaseDirectory -Recurse -Force
    }
    if (Test-Path -LiteralPath $catalogPath) {
        Remove-Item -LiteralPath $catalogPath -Force
    }
    $buildFull = [System.IO.Path]::GetFullPath((Join-Path $repository 'build')).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $testRootFull = [System.IO.Path]::GetFullPath($testRoot)
    if (-not $testRootFull.StartsWith($buildFull, [StringComparison]::OrdinalIgnoreCase) -or
        -not [System.IO.Path]::GetFileName($testRootFull).StartsWith('installer-bundle-test-', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to delete a test directory outside build: $testRootFull"
    }
    if ($buildWasRun) {
        if ($hadPreviousApk) {
            Copy-Item -LiteralPath $previousApk -Destination $defaultApkPath -Force
        } elseif (Test-Path -LiteralPath $defaultApkPath) {
            Remove-Item -LiteralPath $defaultApkPath -Force
        }
    }
    if (Test-Path -LiteralPath $testRootFull) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
